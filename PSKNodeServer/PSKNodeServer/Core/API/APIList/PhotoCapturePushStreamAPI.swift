//
//  PhotoCapturePushStreamAPI.swift
//  PSKNodeServer
//
//  Created by Costin Andronache
//

import PSSmartWalletNativeLayer
import CoreVideo

final class PhotoCapturePushStreamAPI {
    typealias ViewControllerProvider = DataMatrixScanAPI.ViewControllerProvider
    private let frameCaptureModuleBuilder: CameraFrameCaptureModuleBuildable
    private var frameCaptureModuleInput: CameraFrameCaptureModuleInput?
    private var mainChannel: MainChannel?
    private var options: CaptureOptions = .init(captureType: .rgba)
    init(frameCaptureModuleBuilder: CameraFrameCaptureModuleBuildable) {
        self.frameCaptureModuleBuilder = frameCaptureModuleBuilder
    }
}

extension PhotoCapturePushStreamAPI: PushStreamAPIImplementation {
    func openChannel(input: [APIValue], named: String, completion: @escaping (Result<PushStreamChannel, APIError>) -> Void) {
        // name and input irrelevant for now
        guard let frameCaptureModuleInput = self.frameCaptureModuleInput else {
            return
        }
        
        let mainChannel = MainChannel(frameCaptureModuleInput: frameCaptureModuleInput,
                                      captureOptions: options)
        self.mainChannel = mainChannel
        completion(.success(mainChannel))
    }
    
    func openStream(input: [APIValue], _ completion: @escaping (Result<Void, APIError>) -> Void) {
        options = {
            guard input.count >= 2,
                  case .string(let stringValue) = input[0],
                  let captureType = PhotoCaptureType(rawValue: stringValue),
                  case .number(let numberValue) = input[1],
                  numberValue > 0 else {
                      return .init(captureType: .rgba, fps: 10)
                  }
            return .init(captureType: captureType, fps: .init(numberValue))
        }()
        
        let pixelFormat: CameraFrameCapture.PixelFormat = {
            switch options.captureType {
            case .jpegBase64:
                return .defaultDeviceFormat
            case .bgra, .rgba:
                return .BGRA32
            }
        }()
        
        frameCaptureModuleBuilder.build(pixelFormat: pixelFormat,
                                        completion: { initializer in
            initializer.initializeModuleWith(completion: {
                switch $0 {
                case .failure(let error):
                    completion(.failure(.init(code: error.code)))
                case .success(let input):
                    self.frameCaptureModuleInput = input
                    completion(.success(()))
                }
            })
        })
    }
    
    func close() {
        frameCaptureModuleInput?.cancelFrameCapture()
    }
}

private extension PhotoCapturePushStreamAPI {
    final class MainChannel: PushStreamChannel {
        private var timer: Timer?
        private let frameCaptureModuleInput: CameraFrameCaptureModuleInput
        private let captureOptions: CaptureOptions
        private var dataListener: PushStreamChannelDataListener?
        
        init(frameCaptureModuleInput: CameraFrameCaptureModuleInput,
             captureOptions: CaptureOptions) {
            self.frameCaptureModuleInput = frameCaptureModuleInput
            self.captureOptions = captureOptions
        }
        
        func setListeners(_ dataListener: @escaping PushStreamChannelDataListener,
                          _ asciiListener: @escaping PushStreamChannelDataASCIIListener) {
            self.dataListener = dataListener
            switch captureOptions.captureType {
            case .jpegBase64:
                beginRetrievingJPEGBase64()
            case .rgba:
                beginRetrievingBGRAFrames(bufferProcessing: { $0.copyBGRAToRGBA() })
            case .bgra:
                beginRetrievingBGRAFrames(bufferProcessing: { $0.copyBGRABuffer() })
            }
        }
                
        func handlePeerData(_ data: Data) {
            // unhandled here
        }
        
        func close() {
            timer?.invalidate()
            frameCaptureModuleInput.cancelFrameCapture()
        }
        
        private func beginRetrievingJPEGBase64() {
            frameCaptureModuleInput.setCaptureFrameHandler(handler: { [weak self] in
                switch $0 {
                case .success(let buffer):
                    guard let jpegData = buffer.asUIImage?.jpegData(compressionQuality: 1.0),
                          let messageData = ("data:image/jpeg;base64," + jpegData.base64EncodedString()).data(using: .ascii) else {
                        // Must send another object
                        return
                    }
                    self?.dataListener?(messageData, true)
                case .failure:
                    // Must send another object
                    break
                }
            }, isContinuous: true)
        }
        
        private func beginRetrievingBGRAFrames(bufferProcessing: @escaping (CVImageBuffer) -> UnsafeMutableRawPointer?) {
            timer = Timer.scheduledTimer(withTimeInterval: captureOptions.fps?.frameDuration ?? 10,
                                         repeats: true,
                                         block: { [weak self] _ in
                self?.frameCaptureModuleInput.setCaptureFrameHandler(handler: { [weak self] in
                    switch $0 {
                    case .success(let imageBuffer):
                        guard let buffer = bufferProcessing(imageBuffer) else {
    //                        into(.failure(.init(code: CameraFrameCapture
    //                                                .FrameCaptureError
    //                                                .frameCaptureFailure(nil)
    //                                                .code
    //                                           )))
                            return
                        }
                        
                        let data = Data(bytesNoCopy: buffer,
                                        count: imageBuffer.byteCount,
                                        deallocator: .free)
                        
                        self?.dataListener?(.from(value: Int32(imageBuffer.rgba8888Width)), false)
                        self?.dataListener?(.from(value: Int32(imageBuffer.height)), false)
                        self?.dataListener?(data, true)
                    case .failure(let error):
    //                    into(.failure(.init(code: error.code)))
                        break
                    }
                }, isContinuous: false)
            })
            
        }
        
    }
}
