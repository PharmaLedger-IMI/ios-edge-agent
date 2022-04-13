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
    private let mainWebServer = GCDWebServer()
    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    @IBOutlet private var webHostView: PSKWebViewHostView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Configuration.defaultInstance.webviewBackgroundColor
        
        webHostView?.constrain(webView: webView)
        let apiCollection = APICollection.setupAPICollection(webServer: mainWebServer,
                                                             viewControllerProvider: self)
        
        ac.setupStackWith(apiCollection: apiCollection,
                          webServer: mainWebServer,
                          completion: { [weak self] (result) in
            switch result {
            case .success(let url):
                self?.webView.load(.init(url: url))
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
        
        GCDWebServer.setLogLevel(0)
    }

    func loadURL(string: String) {
        if let url = URL(string: string) {
            webView.load(URLRequest(url: url))
        }
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
