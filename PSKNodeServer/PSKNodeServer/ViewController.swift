//
//  ViewController.swift
//  PSSmartWalletNativeLayerDemo
//
//  Created by Costin Andronache on 10/22/20.
//

import PSSmartWalletNativeLayer
import GCDWebServers
import WebKit
import UIKit

class ViewController: UIViewController {
    private let ac = ApplicationCore()
    private let apiContainerServer = GCDWebServer()
    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    @IBOutlet private var webHostView: PSKWebViewHostView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Configuration.defaultInstance.webviewBackgroundColor
        
        webHostView?.constrain(webView: webView)
        loadPreloader()
        
        let apiCollection = APICollection.setupAPICollection(webServer: apiContainerServer,
                                                             viewControllerProvider: self)
        
        ac.setupStackWith(apiCollection: apiCollection,
                          apiContainerServer: apiContainerServer,
                          completion: { [weak self] (result) in
            switch result {
            case .success(let url):
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5,
                                              execute: {
                    let origin = "\(url.scheme ?? "")://\(url.host ?? ""):\(url.port ?? 8080)"
                    let cookie: AuthorizationCookie = .init(name: "Auth",
                                                            token: UUID().uuidString,
                                                            origin: origin)
                    self?.loadSecureCookieThenRedirect(cookie: cookie,
                                                       url: url)                    
                })
            case .failure(let error):
                let message = "\(error.description)\n\("error_final_words".localized)"
                UIAlertController.okMessage(in: self, message: message, completion: nil)
            }
        }, reloadCallback: { [weak self] result in
            switch result {
            case .success:
                return
            case .failure(let error):
                UIAlertController.okMessage(in: self, message: "\(error.description)\n\("error_final_words".localized)", completion: nil)
            }
        })
    }
    
    func loadPreloader() {
        let loaderPathPart = "nodejsProject/preloader"
        guard let loaderPath = Bundle.main.path(forResource: loaderPathPart,
                                                ofType: "html"),
              let loaderHTML = try? String(contentsOfFile: loaderPath) else {
            print("DIDNT FIND preloader")
            return
        }
        webView.loadHTMLString(loaderHTML, baseURL: nil)
    }

    func loadURL(string: String) {
        if let url = URL(string: string) {
            webView.load(URLRequest(url: url))
        }
    }
    
    func loadSecureCookieThenRedirect(cookie: AuthorizationCookie,
                                      url: URL) {
        let webServerURL = URL(string: "http://localhost:\(apiContainerServer.port)/initialLoad")
        ac.setSecurityCookie(cookie: cookie)
        apiContainerServer.addHandler(forMethod: "GET",
                                 path: "/initialLoad",
                                 request: GCDWebServerRequest.classForCoder())
        { (request, completion) in
            let response = GCDWebServerResponse(redirect: url,
                                                permanent: true)
            response.setValue("\(cookie.name)=\(cookie.token); Max-Age=\(60*60*60*24)",
                              forAdditionalHeader: "Set-Cookie")
            completion(response)
        }
        webView.load(.init(url: webServerURL!))
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
}

extension ApplicationCore.SetupError {
    var description: String {
        switch self {
        case .nodePortSearchFail:
            return "port_search_fail_node".localized
        case .apiContainerPortSearchFail:
            return "port_search_fail_ac".localized
        case .apiContainerSetupFailed(let error):
            return "\("ac_setup_failed".localized) \(error.localizedDescription)"
        case .nspSetupError(let error):
            return "\("nsp_setup_failed".localized) \(error.localizedDescription)"
        case .webAppCopyError(let error):
            return "\("web_app_copy_failed".localized) \(error.localizedDescription)"
        case .unknownError(let error):
            return "\("unknown_error".localized) \(error.localizedDescription)"
        }
    }
}

extension ApplicationCore.RestartError {
    var description: String {
        switch self {
        case .foregroundRestartError(let error):
            return "\("unknown_error".localized) \(error.localizedDescription)"
        }
    }
}
