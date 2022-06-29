//
//  StaticPageViewController.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 13.04.2022.
//

import GCDWebServers
import PSSmartWalletNativeLayer
import Foundation
import WebKit
import UIKit

final class StaticPageViewController: UIViewController {
    private var apiContainer: APIContainer?
    private let webServer = GCDWebServer()
    private let ac = ApplicationCore()
    private let webView = WKWebView(frame: .zero, configuration: .init())
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.constrainFull(other: webView)
        let apiCollection = APICollection.setupAPICollection(webServer: webServer,
                                                             viewControllerProvider: self)
        apiContainer = try! ac.setupApiContainer(apiCollection: apiCollection,
                                                 webServer: webServer)
        setupDemoPage(apiPort: apiContainer!.port)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
            let url: URL = .init(string: "http://localhost:\(self.webServer.port)/web-app/index.html")!
            
            self.loadSecureCookieThenRedirect(cookie: .init(name: "Cookiiie", token: "Tolkien", origin: "http://localhost:\(self.webServer.port)"), url: url)
        })
    }
    
    func loadSecureCookieThenRedirect(cookie: AuthorizationCookie,
                                      url: URL) {
        let webServerURL = URL(string: "http://localhost:\(webServer.port)/initialLoad")
        ac.setSecurityCookie(cookie: cookie)
        webServer.addHandler(forMethod: "GET",
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
    
    private func setupDemoPage(apiPort: UInt) {
        let webAppDirectory = Bundle.main.path(forResource: "nativePageDemo", ofType: "")!
        webServer.addHandler(forMethod: "GET", path: "/nsp", request: GCDWebServerRequest.classForCoder()) { (request, completion) in
            let data = "\(apiPort)".data(using: .ascii)!
            completion(GCDWebServerDataResponse(data: data, contentType: "application/octet-stream").applyCORSHeaders())
        }
        
        let basePath = "/web-app/"
        webServer.addGETHandler(forBasePath: basePath, directoryPath: webAppDirectory, indexFilename: "index", cacheAge: 3500, allowRangeRequests: true);
        
        webServer.start()
    }
    ///
}








extension GCDWebServerResponse {
    func applyCORSHeaders() -> Self {
        let resp = self
        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Methods")
        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Headers")
        resp.setValue("true", forAdditionalHeader: "Access-Control-Allow-Credentials")
        return self
    }
}
