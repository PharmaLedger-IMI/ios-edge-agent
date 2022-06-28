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
                        webServer: GCDWebServer,
                        completion: Completion?,
                        reloadCallback: ReloadCallback?) {
        
        do {
            self.reloadCallback = reloadCallback
            let apiContainer = try setupApiContainer(apiCollection: apiCollection,
                                                     webServer: webServer)
            self.apiContainer = apiContainer
            let indexPage = try setupNodeServer(path: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path, apiContainerPort: apiContainer.port)
            
            NetworkUtilities.executeWhenUrlAvilable(url: indexPage) {
                completion?(.success(indexPage))
                self.indexPageURL = indexPage
            }
            
        } catch let error as ApplicationCore.SetupError {
            completion?(.failure(error))
        } catch {
            completion?(.failure(.unknownError(error)))
        }
    }

    private func setupNodeServer(path: String, apiContainerPort: UInt) throws -> URL {
        guard let port = NetworkUtilities.findFreePort() else {
            throw ApplicationCore.SetupError.nodePortSearchFail
        }
        
        let sourceInstallationFolder = Bundle.main.path(forResource: "nodejsProject", ofType: nil) ?? ""
        
        let rootInstallationFolder = "\(path)/nodejsProject"
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
        
        let serverLauncher: String =  "\(path)/nodejsProject/MobileServerLauncher.js"
        let pskServerPath =  "\(path)/nodejsProject/pskWebServer.js"
        let apihubRootPath =  "\(path)/nodejsProject/apihub-root"
        
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
        
        return URL(string: "http://localhost:\(port)/app/loader/")!
    }
    
    func setupApiContainer(apiCollection: APICollection,
                           webServer: GCDWebServer) throws -> APIContainer {
        guard let port = NetworkUtilities.findFreePort() else {
            throw ApplicationCore.SetupError.apiContainerPortSearchFail
        }
        
        do {
            let apiContainer = try APIContainer(mode: .apiOnly(selectedPort: UInt(port)),
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
                    self.reloadCallback?(.success(()))
                }
            }
            
        } catch let error {
            reloadCallback?(.failure(.foregroundRestartError(error)))
        }
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
    typealias ReloadCallback = (Result<Void, RestartError>) -> Void
}
