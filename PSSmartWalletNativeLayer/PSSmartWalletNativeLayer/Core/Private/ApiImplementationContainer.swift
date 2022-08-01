//
//  ApiImplementationContainer.swift
//  PSSmartWalletNativeLayer
//
//  Created by Costin Andronache on 10/28/20.
//

import Foundation
import GCDWebServers

final class ImplementationContainer {
    private var apiImplementationMap: [String: APIImplementation] = [:]
    private var dataStreamAPIImplementationMap: [String: DataStreamAPIImplementation] = [:]
    private var streamAPIImplementationMap: [String: StreamAPIImplementation] = [:]
    private var pushStreamAPIImplementationMap: [String: PushStreamAPIImplementation] = [:]
    private var openedPushStreamChannels: [String: PushStreamChannel] = [:]
    private let dataStorage = DataStorage()
    
    private var webServer: GCDWebServer?
    private var websocketServer: WebSocketServer?
    
    var authorizationCookie = AuthorizationCookie(name: "", token: "", origin: "")
    
    private let internalResultProcessingQueue = DispatchQueue(label: "PSSmartWalletNativeLayer.internalResultProcessingQueue",
                                                              qos: .default,
                                                              attributes: [],
                                                              autoreleaseFrequency: .workItem,
                                                              target: nil)
    
    func addAPI(name: String, implementation: @escaping APIClosureImplementation) throws {
        try addAPI(name: name, implementation: APIClosureImplementationContainer(implementation))
    }
            
    func addAPI(name: String, implementation: APIImplementation) throws {
        guard apiImplementationMap[name] == nil else {
            throw Error.nameAlreadyInUse(apiName: name)
        }
        
        apiImplementationMap[name] = implementation
    }
    
    func addStreamAPI(name: String, implementation: StreamAPIImplementation) throws {
        guard streamAPIImplementationMap[name] == nil else {
            throw Error.nameAlreadyInUse(apiName: name)
        }
        
        streamAPIImplementationMap[name] = implementation
    }
    
    func addPushStreamAPI(name: String, implementation: PushStreamAPIImplementation) throws {
        guard pushStreamAPIImplementationMap[name] == nil else {
            throw Error.nameAlreadyInUse(apiName: name)
        }
        
        pushStreamAPIImplementationMap[name] = implementation
    }
    
    func addDataStreamAPI(name: String, implementation: @escaping DataStreamAPIImplementation) throws {
        guard dataStreamAPIImplementationMap[name] == nil else {
            throw Error.nameAlreadyInUse(apiName: name)
        }
        
        dataStreamAPIImplementationMap[name] = implementation
    }
    
    func setupEndpointIn(server: GCDWebServer) {
        webServer = server
        setupBytesDownloadEndpointIn(server: server)
        setupAPICallEndpointIn(server: server)
        websocketServer = .init(portNumber: NetworkUtilities.findFreePort()!)
        websocketServer?.newConnectionInitializedHandler = { [weak self] conn, data in
            guard let channelID = String(data: data, encoding: .ascii),
                  let channel = self?.openedPushStreamChannels[channelID] else {
                return
            }
            
            channel.setListeners({ [weak conn] in
                conn?.send(data: $0, isComplete: $1)
            }, { [weak conn] in
                conn?.send(ascii: $0, isComplete: $1)
            })
            
            conn.didReceive = { [weak channel] in
                channel?.handlePeerData($0)
            }
            
            conn.send(ascii: "READY", isComplete: true)
        }
        try? websocketServer?.start()
    }
    
    private func setupBytesDownloadEndpointIn(server: GCDWebServer) {
        server.addHandler(forMethod: "GET", path: "/retrieve-resource", request: GCDWebServerRequest.classForCoder()) { [weak self] (request, completion) in
            guard let id = request.query?["id"],
                  let data = self?.dataStorage.removeFrom(id: id),
                  self?.authorizationCookie.verifiedIn(request: request) == true  else {
                completion(nil)
                return
            }
            completion(GCDWebServerDataResponse(data: data, contentType: "application/octet-stream").applyCORSHeaders(serverOrigin: self?.authorizationCookie.origin))
        }
    }
    
    private func setupAPICallEndpointIn(server: GCDWebServer) {
        server.addDefaultHandler(forMethod: "POST", request: GCDWebServerMultiPartFormRequest.classForCoder()) { [weak self] (request, completion) in
            guard let multiPartRequest = request as? GCDWebServerMultiPartFormRequest,
                  let callType = self?.determineAPITypeCall(from: multiPartRequest.url),
                  self?.authorizationCookie.verifiedIn(request: request) == true else {
                      self?.completeWith(error: .noSuchApiError,
                                         completion: completion)
                      return
                  }
            
            self?.dispatchAPICall(type: callType,
                                 arguments: multiPartRequest.arguments.map(\.asAPIValue),
                                 completion: completion)
        }
    }
    
    private func dispatchAPICall(type: APITypeCall,
                                 arguments: [APIValue],
                                 completion: @escaping GCDWebServerCompletionBlock) {
        switch type {
        case .general(let name):
            if let api = apiImplementationMap[name] {
                handleApiCall(api: api, arguments: arguments, completion: completion)
                return
            } else if let streamApi = dataStreamAPIImplementationMap[name] {
                handleDataStreamCall(api: streamApi, arguments: arguments, completion: completion)
                return
            } else {
                completeWith(error: .noSuchApiError, completion: completion)
            }
            
        case .stream(let name, let action):
            handleStreamAPICall(name: name,
                                arguments: arguments,
                                action: action,
                                completion: completion)
        case .pushStream(let type):
            handlePushStreamAPICall(pushStreamCallType: type,
                                    arguments: arguments,
                                    completion: completion)
        }
    }
    
    private func handleApiCall(api: APIImplementation,
                               arguments: [APIValue],
                               completion: @escaping GCDWebServerCompletionBlock) {
        DispatchQueue.main.async {
            api.perform(arguments) {
                switch $0 {
                case .success(let values):
                    self.completeWith(values: values, completion: completion)
                case .failure(let error):
                    self.completeWith(error: error, completion: completion)
                }
            }
        }
    }
    
    private func handleDataStreamCall(api: @escaping DataStreamAPIImplementation,
                                      arguments: [APIValue],
                                      completion: @escaping GCDWebServerCompletionBlock) {
        let authorizationCookie = self.authorizationCookie
        DispatchQueue.main.async {
            api(arguments) { result in
                switch result {
                case .success(let sessionDelegate):
                    completion(GCDWebServerStreamedResponse.init(contentType: "application/octet-stream", asyncStreamBlock: { (bodyBlock) in
                        sessionDelegate.provideNext { (action) in
                            switch action {
                            case .chunk(let data):
                                bodyBlock(data, nil)
                            case .close:
                                bodyBlock(Data(), nil)
                            }
                        }
                    }).applyCORSHeaders(serverOrigin: authorizationCookie.origin).applyStreamHeader())
                case .failure(let error):
                    self.completeWith(error: error, completion: completion)
                }
                
            }
        }
    }
    
    private func handleStreamAPICall(name: String,
                                     arguments: [APIValue],
                                     action: StreamAPIAction,
                                     completion: @escaping GCDWebServerCompletionBlock) {
        guard let api = streamAPIImplementationMap[name] else {
            completeWith(error: .noSuchApiError, completion: completion)
            return
        }
        
        switch action {
        case .open:
            api.openStream(input: arguments, completion: { [weak self] in
                switch $0 {
                case .failure(let error):
                    self?.completeWith(error: error, completion: completion)
                case .success:
                    self?.completeWith(values: [], completion: completion)
                }
            })
        case .nextValue:
            api.retrieveNext(input: arguments, into: { [weak self] in
                switch $0 {
                case .failure(let error):
                    self?.completeWith(error: error, completion: completion)
                case .success(let values):
                    self?.completeWith(values: values, completion: completion)
                }
            })
        case .close:
            api.close()
            completeWith(values: [], completion: completion)
        }
    }
    
    private func handlePushStreamAPICall(pushStreamCallType: APITypeCall.PushStreamCallType,
                                         arguments: [APIValue],
                                         completion: @escaping GCDWebServerCompletionBlock) {
        guard let wsURL = websocketServer?.wsURL else {
            completeWith(error: .noSuchApiError, completion: completion)
            return
        }
        
        switch pushStreamCallType {
        case .close(let apiName):
            guard let pushStreamAPI = pushStreamAPIImplementationMap[apiName] else {
                completeWith(error: .noSuchApiError, completion: completion)
                return
            }
            pushStreamAPI.close()
            completeWith(values: [], completion: completion)
        case .open(let apiName):
            guard let pushStreamAPI = pushStreamAPIImplementationMap[apiName] else {
                completeWith(error: .noSuchApiError, completion: completion)
                return
            }
            pushStreamAPI.openStream(input: arguments, { [weak self] in
                switch $0 {
                case .success:
                    self?.completeWith(values: [], completion: completion)
                case .failure(let error):
                    self?.completeWith(error: error, completion: completion)
                }
            })
        case .connect(let apiName, let channelName):
            guard let pushStreamAPI = pushStreamAPIImplementationMap[apiName] else {
                completeWith(error: .noSuchApiError, completion: completion)
                return
            }
            pushStreamAPI.openChannel(input: arguments,
                                      named: channelName,
                                      completion: { [weak self] in
                switch $0 {
                case .failure(let error):
                    self?.completeWith(error: error, completion: completion)
                case .success(let channel):
                    let channelID = "\(apiName)-\(channelName)"
                    self?.openedPushStreamChannels[channelID] = channel
                    self?.completeWith(values: [.string(wsURL), .string(channelID)],
                                 completion: completion)
                }
            })
        }
    }
    
    private func completeWith(error: APIError, completion: @escaping GCDWebServerCompletionBlock) {
        completion(GCDWebServerDataResponse(jsonObject: ["error": error.code])?.applyCORSHeaders(serverOrigin: authorizationCookie.origin))
    }
    
    private func completeWith(values: [APIValue], completion: @escaping GCDWebServerCompletionBlock) {

        let jsonArray = values.map({ (value) -> [String: Any] in
            value.jsonWithMetadata(origin: webServer?.serverOrigin ?? "",
                                   bytesIdGenerator: { self.dataStorage.insert(data: $0) })
        })
        completion(GCDWebServerDataResponse(jsonObject: ["result": jsonArray])?.applyCORSHeaders(serverOrigin: authorizationCookie.origin))
    }
}

private extension AuthorizationCookie {
    func verifiedIn(request: GCDWebServerRequest) -> Bool {
        guard let requestCookie = (request.headers["Cookie"] ?? request.headers["cookie"]) else {
            print("NO COOKIES")
            return false
        }
        let verified = requestCookie.contains(name) && requestCookie.contains(token)
        print("COOKIE VERIFIED: \(verified)")
        return true
    }
}

private extension ImplementationContainer {
    enum StreamAPIAction: String {
        case open
        case nextValue
        case close
    }

    enum APITypeCall {
        enum PushStreamCallType {
            case open(apiName: String)
            case close(apiName: String)
            case connect(streamID: String, channelName: String)
        }
        case general(apiName: String)
        case stream(apiName: String, action: StreamAPIAction)
        case pushStream(PushStreamCallType)
    }
    
    func determineAPITypeCall(from url: URL) -> APITypeCall? {
        // general API call: <server_url>/apiName
        // poll stream API call: <server_url>/apiName/{open|nextValue|close}
        // push stream API call: <server_url>/pushStream/open/{apiName} |
        // push stream API call: <server_url>/pushStream/close/{apiName} |
        //                       <server_url>/pushStream/connect/{apiName}/{channelName}
        
        if let pushStreamType = determinePushStreamCallType(from: url) {
            return .pushStream(pushStreamType)
        }
                
        let components = url.pathComponents
        guard let lastComponent = components.last else {
            print("Empty components, no APIType");
            return nil
        }
        
        if let streamAPIAction = StreamAPIAction(rawValue: lastComponent) {
            guard components.count >= 2 else {
                print("No viable component found in \(components)")
                return nil
            }
            return .stream(apiName: components[components.count-2], action: streamAPIAction)
        }
        
        return .general(apiName: lastComponent)
    }
    
    func determinePushStreamCallType(from url: URL) -> APITypeCall.PushStreamCallType? {
        let components = url.pathComponents
        guard components.contains("pushStream") else {
            return nil
        }
        
        func matchOpen() -> APITypeCall.PushStreamCallType? {
            guard components.contains("open"),
                  let apiName = components.last,
                  apiName != "open" else {
                return nil
            }
            return .open(apiName: apiName)
        }
        
        func matchClose() -> APITypeCall.PushStreamCallType? {
            guard components.contains("close"),
                  let apiName = components.last,
                  apiName != "close" else {
                return nil
            }
            return .close(apiName: apiName)
        }
        
        func matchConnect() -> APITypeCall.PushStreamCallType? {
            guard components.count >= 3, components[components.count - 3] == "connect" else {
                return nil
            }
            return .connect(streamID: components[components.count - 2],
                            channelName: components[components.count - 1])
        }
        
        return matchOpen() ?? matchConnect() ?? matchClose()
    }
}

private struct APIClosureImplementationContainer: APIImplementation {
    let implementation: APIClosureImplementation
    init(_ implementation: @escaping APIClosureImplementation) {
        self.implementation = implementation
    }
    
    func perform(_ inputArguments: [APIValue], _ completion: @escaping APIResultCompletion) {
        implementation(inputArguments, completion)
    }
}

private extension GCDWebServerMultiPartArgument {
    var asAPIValue: APIValue {
        if let string = string {
            if let number = Double(string) {
                return .number(number)
            } else {
                return .string(string)
            }
        } else {
            return .bytes(data)
        }
    }
}

private extension APIValue {
    func jsonWithMetadata(origin: String, bytesIdGenerator: @escaping (Data) -> String) -> [String: Any] {
        switch self {
        case .string(let string): return ["type": "string", "value": string]
        case .number(let double): return ["type": "number", "value": double]
        case .bytes(let data): return ["type": "bytes",
                                       "path": "\(origin)/retrieve-resource?id=\(bytesIdGenerator(data))"]
        }
    }
}
