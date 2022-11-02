//
//  ApplicationCore.swift
//
//

import UIKit
import GCDWebServers
import PSSmartWalletNativeLayer

final class ApplicationCore {
    private var apiContainer: APIContainer?
    private var reloadCallback: ReloadCallback?
    private var rootInstallationFolder = ""
    private var indexPageURL: URL?
    private var ignoredFirstForeground: Bool = false
    
    func setSecurityCookie(cookie: AuthorizationCookie) {
        apiContainer?.authorizationCookie = cookie
    }
    
    func setupStackWith(apiCollection: APICollection,
                        apiContainerServer: GCDWebServer,
                        completion: Completion?,
                        reloadCallback: ReloadCallback?) {
        
        do {
            let apiContainerPort = try start(webServer: apiContainerServer)
            self.reloadCallback = reloadCallback
            let apiContainer = try setupApiContainer(apiCollection: apiCollection,
                                                     webServer: apiContainerServer)
            self.apiContainer = apiContainer
            let nodePort = try setupNodeWithServerFilesInto(directoryPath: FileManager.default.urls(for: .documentDirectory,
                                                                                                    in: .userDomainMask).first!.path,
                                                            apiContainerPort: UInt(apiContainerPort))
            
            let nodeURL = URL(string: "http://localhost:\(nodePort)/environment.js")!

            let webAppURL = try! self.setupWebAppServerIntoAPIContainer(webserver: apiContainerServer,
                                                                        nodePort: nodePort,
                                                                        apiContainerPort: apiContainerPort)
            NetworkUtilities.executeWhenUrlAvilable(url: nodeURL, job: {
                completion?(.success(webAppURL))
                self.indexPageURL = webAppURL
            })
            
        } catch let error as ApplicationCore.SetupError {
            completion?(.failure(error))
        } catch {
            completion?(.failure(.unknownError(error)))
        }
    }
    
    @discardableResult
    private func start(webServer: GCDWebServer) throws -> UInt16 {
        let startFromPort: (UInt16?, GCDWebServer) throws -> UInt16 = {
            var port: UInt16 = $0 ?? 8600
            while !$1.start(withPort: UInt(port), bonjourName: nil) && port < 9999 {
                port += 1
            }
            
            if port == 9999 {
                throw Error.noAvailablePort
            }
            
            return port
        }
        return try startFromPort(NetworkUtilities.findFreePort(), webServer)
    }

    private func setupNodeWithServerFilesInto(directoryPath: String,
                                              apiContainerPort: UInt) throws -> UInt16 {
        guard let port = NetworkUtilities.findFreePort() else {
            throw ApplicationCore.SetupError.nodePortSearchFail
        }
        
        let serverFilesPathPart = "nodejsProject"
        let sourceInstallationFolder = (Bundle.main.path(forResource: serverFilesPathPart,
                                                        ofType: nil) ?? "") + "/serverFiles"
        
        let rootInstallationFolder = "\(directoryPath)/\(serverFilesPathPart)"
        self.rootInstallationFolder = rootInstallationFolder
        
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: rootInstallationFolder, isDirectory: nil) {
            print("Begin copying into \(rootInstallationFolder)")
            do {
                try fm.copyItem(atPath: sourceInstallationFolder, toPath: rootInstallationFolder)
                print("DONE COPYING");
                
            } catch let error {
                throw ApplicationCore.SetupError.webAppCopyError(error)
            }
        }
        
        let nspPath = "\(rootInstallationFolder)/apihub-root/nsp"
        do {
            try "\(apiContainerPort)".data(using: .ascii)?.write(to: .init(fileURLWithPath: nspPath))
        } catch let error {
            throw ApplicationCore.SetupError.nspSetupError(error)
        }
        
        let serverLauncher: String = "\(rootInstallationFolder)/MobileServerLauncher.js"
        let pskServerPath = "\(rootInstallationFolder)/pskWebServer.js"
        let apihubRootPath = "\(rootInstallationFolder)/apihub-root"
        
        let env: [String: String] = [
            "PSK_CONFIG_LOCATION": "\(apihubRootPath)/external-volume/config",
            "PSK_ROOT_INSTALATION_FOLDER": rootInstallationFolder,
            "BDNS_ROOT_HOSTS": "http://localhost:\(port)"
        ]
        let envString = String(data: try! JSONEncoder().encode(env), encoding: .ascii)!
        
        Thread {
            NodeRunner.startEngine(withArguments: ["node", serverLauncher, "--bundle=\(pskServerPath)",
                                                   "--port=\(port)", "--rootFolder=\(apihubRootPath)",
                                                   "--env=\(envString)"])
        }.start()
        
        return port
    }
    
    func setupApiContainer(apiCollection: APICollection,
                           webServer: GCDWebServer) throws -> APIContainer {
        do {
            let apiContainer = try APIContainer(mode: .apiOnly,
                                                webserver: webServer)
            try apiCollection.apiList.forEach {
                try apiContainer.addAPI(name: $0.name, implementation: $0.impl)
            }
            
            try apiCollection.streamAPIList.forEach {
                try apiContainer.addStreamAPI(name: $0.name, implementation: $0.impl)
            }
            
            try apiCollection.pushStreamAPIList.forEach {
                try apiContainer.addPushStreamAPI(name: $0.name, implementation: $0.impl)
            }
            
            setupBackgroundListeners()
            return apiContainer
        } catch let error {
            throw ApplicationCore.SetupError.apiContainerSetupFailed(error)
        }
    }
    
    private func handleRedirectionFor(apiContainerPort: UInt16,
                                      nodePort: UInt16,
                                      request: GCDWebServerRequest,
                                      completion: @escaping GCDWebServerCompletionBlock) {
        let fm = FileManager.default
        let webAppFilesPathPart = "nodejsProject/app"
        guard let webAppInstallationFolder = Bundle.main.path(forResource: webAppFilesPathPart,
                                                              ofType: nil) else {
            completion(nil)
            return
        }
        
        if request.url.absoluteString.contains("camera.js") {
            let filePath = webAppInstallationFolder + "/camera.js"
            let response = GCDWebServerFileResponse(file: filePath)
            completion(response)
            return
        }
        
        
        if request.path == "/nsp" {
            let response = GCDWebServerDataResponse(text: "\(apiContainerPort)")
            completion(response)
            return
        }
        
        if request.path == "/jailbreak/details" {
            if let suspicions = localizedJailbreakSuspicions() {
                let response = GCDWebServerDataResponse(text: suspicions)
                completion(response)
                return
            }
        }
        
        let filePath = webAppInstallationFolder + request.path
        if fm.fileExists(atPath: filePath) {
            let response = GCDWebServerFileResponse(file: filePath)
            completion(response)
        } else {
            print("NOT FOUND FOR: \(request.url), will redirect")
            let nodeURL = "http://localhost:\(nodePort)" + request.path
            var urlRequest = URLRequest(url: URL(string: nodeURL)!)
            urlRequest.httpMethod = request.method
            if request.hasBody() {
                let bodyRequest = request as? GCDWebServerDataRequest
                urlRequest.httpBody = bodyRequest?.data
                print("Body length: \(urlRequest.httpBody?.count ?? 0)")
            }
            urlRequest.allHTTPHeaderFields = request.headers
            
            let task = URLSession.shared.dataTask(with: urlRequest,
                                                  completionHandler: { data, response, error in
                let urlResponse = response as! HTTPURLResponse
                let contentType = urlResponse.value(forHTTPHeaderField: "content-type") ??
                urlResponse.value(forHTTPHeaderField: "Content-Type") ??
                "application/octet-stream"
                                
                let gcdResponse = GCDWebServerDataResponse(data: data!,
                                                           contentType: contentType)
                gcdResponse.statusCode = urlResponse.statusCode
                urlResponse.allHeaderFields.forEach({ key, value in
                    let keyString = key as! String
                    guard !["connection", "keep-alive"].contains(keyString.lowercased()) else {
                        return
                    }
                    let valueString = value as! String
                    gcdResponse.setValue(valueString, forAdditionalHeader: keyString)
                })
                
                completion(gcdResponse)
            })
            task.resume()
        }
    }
    
    private func addRedirectionPointsInto(webserver: GCDWebServer,
                                          apiContainerPort: UInt16,
                                          nodePort: UInt16) {
        let redirectBlock: GCDWebServerAsyncProcessBlock = { [weak self] request, completion in
            self?.handleRedirectionFor(apiContainerPort: apiContainerPort,
                                       nodePort: nodePort,
                                       request: request,
                                       completion: completion)
        }
        
        let regexIgnoringAPICalls = "^((?!\\/nativeApiCall|\\/previewframe|\\/deviceinfo|\\/rawframe_ycbcr).)*$"
        
        webserver.addHandler(forMethod: "GET",
                             pathRegex: regexIgnoringAPICalls,
                             request: GCDWebServerRequest.classForCoder(),
                             asyncProcessBlock: redirectBlock)
        
        webserver.addHandler(forMethod: "POST",
                             pathRegex: regexIgnoringAPICalls,
                             request: GCDWebServerDataRequest.classForCoder(),
                             asyncProcessBlock: redirectBlock)

        webserver.addHandler(forMethod: "PUT",
                             pathRegex: regexIgnoringAPICalls,
                             request: GCDWebServerDataRequest.classForCoder(),
                             asyncProcessBlock: redirectBlock)

        webserver.addHandler(forMethod: "HEAD",
                             pathRegex: regexIgnoringAPICalls,
                             request: GCDWebServerDataRequest.classForCoder(),
                             asyncProcessBlock: redirectBlock)

        webserver.addHandler(forMethod: "OPTIONS",
                             pathRegex: regexIgnoringAPICalls,
                             request: GCDWebServerDataRequest.classForCoder(),
                             asyncProcessBlock: redirectBlock)
    }
    
    private func setupWebAppServerIntoAPIContainer(webserver: GCDWebServer,
                                                   nodePort: UInt16,
                                                   apiContainerPort: UInt16) throws -> URL {
        addRedirectionPointsInto(webserver: webserver, apiContainerPort: apiContainerPort, nodePort: nodePort)
        return URL(string: "http://localhost:\(apiContainerPort)/index.html")!
    }
    
    private func setupWebAppServer(webserver: GCDWebServer,
                                   nodePort: UInt16,
                                   apiContainerPort: UInt16) throws -> URL {
        addRedirectionPointsInto(webserver: webserver, apiContainerPort: apiContainerPort, nodePort: nodePort)
        let port = try start(webServer: webserver)
        return URL(string: "http://localhost:\(port)/index.html")!
    }
    
    private func setupBackgroundListeners() {
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main, using: { (_) in
                self.restartServerOnForeground()
            })
        } else {
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { (_) in
                self.restartServerOnForeground()
            })
        }
    }
    
    private func restartServerOnForeground() {
        guard ignoredFirstForeground else {
            ignoredFirstForeground = true
            return
        }
        
        let needServerRestart = "\(rootInstallationFolder)/apihub-root/needServerRestart"
        do {
            try "NEED_RESTART".data(using: .ascii)?.write(to: .init(fileURLWithPath: needServerRestart))
            if let url = indexPageURL {
                NetworkUtilities.executeWhenUrlAvilable(url: url) {
                    self.reloadCallback?(.success(url))
                }
            }
            
        } catch let error {
            reloadCallback?(.failure(.foregroundRestartError(error)))
        }
    }
    
    private func localizedJailbreakSuspicions() -> String? {
        let suspicions = JailbreakHeuristics().jailbreakSuspicions()
        guard !suspicions.isEmpty else {
            return nil
        }
        
        return suspicions.map(\.localized).joined(separator: "\n")
    }
}

extension ApplicationCore {
    enum SetupError: Swift.Error {
        case nodePortSearchFail
        case apiContainerPortSearchFail
        case apiContainerSetupFailed(Swift.Error)
        case nspSetupError(Swift.Error)
        case webAppCopyError(Swift.Error)
        case unknownError(Swift.Error)
    }
    
    enum RestartError: Swift.Error {
        case foregroundRestartError(Swift.Error)
    }
}

extension ApplicationCore {
    typealias Completion = (Result<URL, SetupError>) -> Void
    typealias ReloadCallback = (Result<URL, RestartError>) -> Void
}
