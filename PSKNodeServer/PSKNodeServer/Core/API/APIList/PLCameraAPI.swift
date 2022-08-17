//
//  PLCameraAPI.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 13.03.2022.
//

import Foundation
import PSSmartWalletNativeLayer
import PharmaLedgerCamera
import GCDWebServers

struct PLCameraAPI: StreamAPIImplementation {
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

enum ErrorCodes {
    static let cameraServerStartFailure = "PLCAMERAAPI_SERVER_START_FAILURE"
    static let messageDecodingFailure = "PLCAMERAAPI_MESSAGE_DECODE_FAILURE"
    static let cameraPermissionDenided = "PLCAMERAAPI_CAMERA_PERMISSION_DENIED"
}

struct PLCameraMessage {
    let name: PharmaledgerMessageHandler.MessageName
    let args: [String: Any]
    
    init?(encodedJSON: String) {
        guard let data = encodedJSON.data(using: .ascii),
              let dict = try? JSONSerialization.jsonObject(with: data,
                                                           options: []) as? [String: Any] else {
                  return nil
              }
        
        guard let nameRaw = dict["name"] as? String,
              let name = PharmaledgerMessageHandler.MessageName(rawValue: nameRaw) else {
                  return nil
              }
        
        let args = dict["args"] as? [String: Any] ?? [:]
        
        self.name = name
        self.args = args
    }
}

extension APIValue {
    var stringCaseValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }
}
