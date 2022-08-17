//
//  WebviewContainer.swift
//  PSSmartWalletNativeLayer
//
//  Created by Costin Andronache on 10/21/20.
//

import Foundation
import WebKit
import GCDWebServers

private let maxPortSearched = 9999
public class APIContainer {
    
    public enum Mode {
        case withWebApp(WebAppConfiguration)
        case apiOnly(selectedPort: UInt?)
    }
    
    public struct WebAppConfiguration {
        public let webAppDirectory: String
        public let indexFilename: String
        public init(webAppDirectory: String,
                    indexFilename: String) {
            self.webAppDirectory = webAppDirectory
            self.indexFilename = indexFilename
        }
    }
    
    private let implementationContainer = ImplementationContainer()
    private let webserver: GCDWebServer
    public let port: UInt
    public var authorizationCookie = AuthorizationCookie(name: "", token: "", origin: "") {
        didSet {
            implementationContainer.authorizationCookie = authorizationCookie
        }
    }
    public var serverOrigin: String {
        webserver.serverOrigin
    }
    public var webAppOrigin: String {
        serverOrigin + "/web-app/"
    }
    
    public init(mode: Mode,
                webserver: GCDWebServer) throws {
        self.webserver = webserver
        implementationContainer.setupEndpointIn(server: webserver)

        let startFromPort: (UInt?, GCDWebServer) throws -> UInt = {
            var port: UInt = $0 ?? 8600
            while !$1.start(withPort: port, bonjourName: nil) && port < maxPortSearched {
                port += 1
            }
            
            if port == maxPortSearched {
                throw Error.noAvailablePort
            }
            
            return port
        }
        
        switch mode {
        case .withWebApp(let configuration):
            let basePath = "/web-app/"
            webserver.addGETHandler(forBasePath: basePath, directoryPath: configuration.webAppDirectory, indexFilename: configuration.indexFilename, cacheAge: 3500, allowRangeRequests: true);
            port = try startFromPort(nil, self.webserver)
        case .apiOnly(let selectedPort):
            port = try startFromPort(selectedPort, self.webserver)
        }
        
        webserver.addDefaultHandler(forMethod: "OPTIONS", request: GCDWebServerRequest.classForCoder()) { [weak self] (req) -> GCDWebServerResponse? in
            return GCDWebServerResponse().applyCORSHeaders(serverOrigin: self?.authorizationCookie.origin)
        }
        GCDWebServer.setLogLevel(4)
    }
    
    public func addAPI(name: String, implementation: @escaping APIClosureImplementation) throws {
        try implementationContainer.addAPI(name: name, implementation: implementation)
    }
    
    public func addAPI(name: String, implementation: APIImplementation) throws {
        try implementationContainer.addAPI(name: name, implementation: implementation)
    }
    
    public func addStreamAPI(name: String, implementation: StreamAPIImplementation) throws {
        try implementationContainer.addStreamAPI(name: name,
                                                 implementation: implementation)
    }
    
    public func addPushStreamAPI(name: String, implementation: PushStreamAPIImplementation) throws {
        try implementationContainer.addPushStreamAPI(name: name,
                                                     implementation: implementation)
    }
    
    public func addDataStreamAPI(name: String, implementation: @escaping DataStreamAPIImplementation) throws {
        try implementationContainer.addDataStreamAPI(name: name, implementation: implementation)
    }
    
}

public extension GCDWebServer {
    var serverOrigin: String {
        "http://localhost:\(port)"
    }
}

extension GCDWebServerResponse {
    func applyCORSHeaders(serverOrigin: String?) -> Self {
        let resp = self
        resp.setValue(serverOrigin ?? "*", forAdditionalHeader: "Access-Control-Allow-Origin")
        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Methods")
        resp.setValue("*", forAdditionalHeader: "Access-Control-Allow-Headers")
        resp.setValue("true", forAdditionalHeader: "Access-Control-Allow-Credentials")
        return self
    }
    
    func applyStreamHeader() -> Self {
        let resp = self;
        resp.setValue("*", forAdditionalHeader: "X-Stream-Header")
        return self;
    }
}

