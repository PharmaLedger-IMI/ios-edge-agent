//
//  PLCameraPushStreamAPI.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 28.07.2022.
//

import Foundation
import UIKit
import PSSmartWalletNativeLayer
import PharmaLedgerCamera
import GCDWebServers

final class PLCameraPushStreamAPI: PushStreamAPIImplementation {
    private let messageHandler: PharmaledgerMessageHandler = .init()
    private let webServer: GCDWebServer
    private var cameraServerHost: String {
        "http://localhost:\(webServer.port)"
    }
    
    private var mainChannel: MainChannel?
    private var secondaryChannel: SecondaryChannel?
    private var rawFrameSimpleChannel: RawFrameChannel?
    private var rawFrameYCBCRChannel: RawFrameChannel?
    
    init() {
        self.webServer = GCDWebServer()
        messageHandler.setupInWebServer(webserver: webServer)
    }
    
    
    func openStream(input: [APIValue], _ completion: @escaping (Result<Void, APIError>) -> Void) {
        webServer.start(withPort: UInt(NetworkUtilities.findFreePort() ?? 10278), bonjourName: nil)
        completion(.success(()))
    }
    
    func openChannel(input: [APIValue],
                     named: String,
                     completion: @escaping (Result<PushStreamChannel, APIError>) -> Void) {
        switch named {
        case "main":
            let mainChannel = MainChannel(messageHandler: messageHandler,
                                          cameraServerHost: cameraServerHost,
                                          onStopEvent: { [weak self] in
                self?.secondaryChannel?.close()
                self?.rawFrameYCBCRChannel?.close()
                self?.rawFrameSimpleChannel?.close()
            })
            self.mainChannel = mainChannel
            completion(.success(mainChannel))
            
        case "secondary":
            let secondaryChannel = SecondaryChannel(messageHandler: messageHandler)
            self.secondaryChannel = secondaryChannel
            completion(.success(secondaryChannel))
        case "rawFrame":
            let channelInput = input.first?.rawFrameChannelInput ?? .defaultValue
            let rawFrameSimpleChannel = RawFrameChannel(type: .simple,
                                                        input: channelInput,
                                                        messageHandler: messageHandler)
            self.rawFrameSimpleChannel = rawFrameSimpleChannel
            completion(.success(rawFrameSimpleChannel))
            
        case "rawFrameYCBCR":
            let channelInput = input.first?.rawFrameChannelInput ?? .defaultValue
            let rawFrameYCBCRChannel = RawFrameChannel(type: .ycbcr,
                                                       input: channelInput,
                                                       messageHandler: messageHandler)
            self.rawFrameYCBCRChannel = rawFrameYCBCRChannel
            completion(.success(rawFrameYCBCRChannel))
        default:
            completion(.failure(.init(code: "NO_SUCH_CHANNEL")))
        }
    }
    
    func close() {
        
    }
    
}

private class MainChannel: PushStreamChannel {
    private let messageHandler: PharmaledgerMessageHandler
    private var dataListener: PushStreamChannelDataListener?
    private var asciiListener: PushStreamChannelDataASCIIListener?
    private let cameraServerHost: String
    private let onStopEvent: VoidBlock?
    
    init(messageHandler: PharmaledgerMessageHandler,
         cameraServerHost: String,
         onStopEvent: VoidBlock?) {
        self.messageHandler = messageHandler
        self.cameraServerHost = cameraServerHost
        self.onStopEvent = onStopEvent
    }
    
    func setListeners(_ dataListener: @escaping PushStreamChannelDataListener,
                      _ asciiListener: @escaping PushStreamChannelDataASCIIListener) {
        self.dataListener = dataListener
        self.asciiListener = asciiListener
    }
    
    func handlePeerData(_ data: Data) {
        guard let encodedJSON = String(data: data, encoding: .ascii),
              let message = PLCameraMessage(encodedJSON: encodedJSON) else {
            return
        }
        
        switch message.name {
        case .StartCamera:
            messageHandler.startCamera(args: message.args,
                                       cameraReadyHandler: {
                self.asciiListener?(self.cameraServerHost, true)
            },
                                       permissionDeniedHandler: {
                //TO DO: encode an error
            })
        case .StartCameraWithConfig:
            messageHandler.startCameraWithConfig(args: message.args,
                                                 cameraReadyHandler: {
                self.asciiListener?(self.cameraServerHost, true)
            },
                                                 permissionDeniedHandler: {
                //TO DO: encode an error
            })
            break
        case .SetFlashMode:
            messageHandler.setFlashMode(args: message.args)
            asciiListener?("SUCCESS", true)
        case .SetPreferredColorSpace:
            messageHandler.setColorSpace(args: message.args)
            asciiListener?("SUCCESS", true)
        case .SetTorchLevel:
            messageHandler.setTorchLevel(args: message.args)
            asciiListener?("SUCCESS", true)
        case .TakePicture:
            messageHandler.takeBase64Picture(args: message.args, completion: {
                self.asciiListener?($0, true)
            })
        case .StopCamera:
            messageHandler.stopCameraSession()
            onStopEvent?()
            asciiListener?("SUCCESS", true)
        @unknown default:
            break
        }
    }
    
    func close() {
        
    }
}

private class SecondaryChannel: PushStreamChannel {
    private let messageHandler: PharmaledgerMessageHandler
    private var dataListener: PushStreamChannelDataListener?
    private var asciiListener: PushStreamChannelDataASCIIListener?
    
    init(messageHandler: PharmaledgerMessageHandler) {
        self.messageHandler = messageHandler
    }
    
    func setListeners(_ dataListener: @escaping PushStreamChannelDataListener,
                      _ asciiListener: @escaping PushStreamChannelDataASCIIListener) {
        self.dataListener = dataListener
        self.asciiListener = asciiListener
    }
    
    func handlePeerData(_ data: Data) {
        guard let message = Message(encodedJSON: data) else {
            return
        }
        
        switch message.callName {
        case .snapshotJPEG:
            messageHandler.getJPEGSnapshot(completion: {
                if let jpegData = $0 {
                    self.dataListener?(jpegData, true)
                }
            })
            
        case .previewFrame:
            guard let frameData = messageHandler.gePreviewFrame() else {
                return
            }
            dataListener?(.from(value: Int32(frameData.width)), false)
            dataListener?(.from(value: Int32(frameData.height)), false)
            dataListener?(frameData.data, true)
            
        case .rawFrame:
            guard let frameData = messageHandler.getRawFrame(roi: message.roi) else {
                return
            }
            dataListener?(.from(value: Int32(frameData.width)), false)
            dataListener?(.from(value: Int32(frameData.height)), false)
            dataListener?(frameData.data, true)
            
        case .rawFrameYCBCR:
            guard let frameData = messageHandler.getRawFrameYCBCR(roi: message.roi) else {
                return
            }
            dataListener?(.from(value: Int32(frameData.width)), false)
            dataListener?(.from(value: Int32(frameData.height)), false)
            dataListener?(frameData.data, true)
            
        case .cameraConfig:
            guard let data = try? JSONSerialization.data(withJSONObject: messageHandler.getCameraConfig(),
                                                         options: .prettyPrinted),
                  let encodedJSON = String(data: data, encoding: .ascii) else {
                      return
                  }
            asciiListener?(encodedJSON, true)
            
        case .deviceInfo:
            guard let data = try? JSONSerialization.data(withJSONObject: messageHandler.getDeviceInfo(),
                                                         options: .prettyPrinted),
                  let encodedJSON = String(data: data, encoding: .ascii) else {
                      return
                  }
            asciiListener?(encodedJSON, true)
        }
    }
    
    func close() {
        
    }
}

private final class RawFrameChannel: PushStreamChannel {
    struct Input: Decodable {
        let x: Int?
        let y: Int?
        let w: Int?
        let h: Int?
        let fps: Int
        
        var roi: CGRect? {
            guard let x = x, let y = y, let w = w, let h = h else {
                return nil
            }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        
        static let defaultValue = Self(x: nil, y: nil, w: nil, h: nil, fps: 10)
    }
    
    enum FrameType {
        case simple
        case ycbcr
    }
    
    private let type: FrameType
    private let input: Input
    private let messageHandler: PharmaledgerMessageHandler
    
    private var dataListener: PushStreamChannelDataListener?
    private var timer: Timer?
    
    init(type: FrameType,
         input: Input,
         messageHandler: PharmaledgerMessageHandler) {
        self.type = type
        self.input = input;
        self.messageHandler = messageHandler
    }
    
    private func pushFrame(data: Data, width: Int32, height: Int32) {
        dataListener?(.from(value: width), false)
        dataListener?(.from(value: height), false)
        dataListener?(data, true)
    }
    
    func setListeners(_ dataListener: @escaping PushStreamChannelDataListener,
                      _ asciiListener: @escaping PushStreamChannelDataASCIIListener) {
        self.dataListener = dataListener
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / CGFloat(input.fps),
                                     repeats: true,
                                     block: { [weak self] _ in
            guard let self = self else {
                return
            }
            switch self.type {
            case .simple:
                guard let frameData = self.messageHandler.getRawFrame(roi: self.input.roi) else {
                    return
                }
                self.pushFrame(data: frameData.data,
                               width: Int32(frameData.width),
                               height: Int32(frameData.height))
            case .ycbcr:
                guard let frameData = self.messageHandler.getRawFrameYCBCR(roi: self.input.roi) else {
                    return
                }
                self.pushFrame(data: frameData.data,
                               width: Int32(frameData.width),
                               height: Int32(frameData.height))
            }
        })
    }
    
    func handlePeerData(_ data: Data) {
        // unhandled, no data expected to be received in this channel
    }
    
    func close() {
        // expecteing the parent stream to close all resources
        timer?.invalidate()
    }
}

private extension SecondaryChannel {
    enum MessageName: String {
        case snapshotJPEG
        case previewFrame
        case rawFrame
        case rawFrameYCBCR
        case cameraConfig
        case deviceInfo
    }
    
    struct Message {
        let callName: MessageName
        let params: [String: Any]
        init?(encodedJSON: Data) {
            guard let dict = try? JSONSerialization.jsonObject(with: encodedJSON,
                                                               options: []) as? [String: Any] else {
                return nil
            }
            
            guard let nameRaw = dict["callName"] as? String,
                  let name = MessageName(rawValue: nameRaw) else {
                      return nil
            }
            
            let args = dict["params"] as? [String: Any] ?? [:]
            
            self.callName = name
            self.params = args
        }
        
        var roi: CGRect? {
            guard let x = params["x"] as? CGFloat,
                  let y = params["y"] as? CGFloat,
                  let w = params["w"] as? CGFloat,
                  let h = params["h"] as? CGFloat else {
                      return nil
                  }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}

private extension APIValue {
    var rawFrameChannelInput: RawFrameChannel.Input? {
        guard let data = stringCaseValue?.data(using: .ascii),
              let input = try? JSONDecoder().decode(RawFrameChannel.Input.self, from: data) else {
            return nil
        }
        return input
    }
}
