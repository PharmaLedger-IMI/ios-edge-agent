//
//  PLCameraPushStreamAPI.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 28.07.2022.
//

import Foundation
import PSSmartWalletNativeLayer
import PharmaLedgerCamera
import GCDWebServers

struct PLCameraPushStreamAPI: StreamAPIImplementation {
    private let messageHandler: PharmaledgerMessageHandler = .init()
    private let webServer: GCDWebServer
    private var cameraServerHost: String {
        "http://localhost:\(webServer.port)"
    }
    
    init(webServer: GCDWebServer) {
        self.webServer = webServer
        messageHandler.setupInWebServer(webserver: webServer)
    }
    
    func openStream(input: [APIValue], completion: @escaping (Result<Void, APIError>) -> Void) {
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }
    
    func retrieveNext(input: [APIValue], into: @escaping (Result<[APIValue], APIError>) -> Void) {
        DispatchQueue.main.async {
            guard let encodedJSON = input.first?.stringCaseValue,
                  let message = PLCameraMessage(encodedJSON: encodedJSON) else {
                      into(.failure(.init(code: ErrorCodes.messageDecodingFailure)))
                      return
                  }
            
            switch message.name {
            case .StartCamera:
                messageHandler.startCamera(args: message.args,
                                           cameraReadyHandler: {
                    into(.success([.string(self.cameraServerHost)]))
                },
                                           permissionDeniedHandler: {
                    into(.failure(.init(code: ErrorCodes.cameraPermissionDenided)))
                })
            case .StartCameraWithConfig:
                messageHandler.startCameraWithConfig(args: message.args,
                                                     cameraReadyHandler: {
                    into(.success([.string(self.cameraServerHost)]))
                },
                                                     permissionDeniedHandler: {
                    into(.failure(.init(code: ErrorCodes.cameraPermissionDenided)))
                })
                break
            case .SetFlashMode:
                messageHandler.setFlashMode(args: message.args)
                into(.success([]))
            case .SetPreferredColorSpace:
                messageHandler.setColorSpace(args: message.args)
                into(.success([]))
            case .SetTorchLevel:
                messageHandler.setTorchLevel(args: message.args)
                into(.success([]))
            case .TakePicture:
                messageHandler.takeBase64Picture(args: message.args, completion: {
                    into(.success([.string($0)]))
                })
            case .StopCamera:
                messageHandler.stopCameraSession()
                into(.success([]))
            @unknown default:
                into(.failure(.init(code: ErrorCodes.messageDecodingFailure)))
                break
            }
        }
    }
    
    func close() { }
}

private class MainChannel: PushStreamChannel {
    private let messageHandler: PharmaledgerMessageHandler
    private var listener: PushStreamChannelDataListener?
    
    init(messageHandler: PharmaledgerMessageHandler) {
        self.messageHandler = messageHandler
    }
    
    func setDataListener(_ listener: @escaping PushStreamChannelDataListener) {
        self.listener = listener
    }
    
    func handlePeerData(_ data: Data) {
        
    }
    
    func close() {
        
    }
}
