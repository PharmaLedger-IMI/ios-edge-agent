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
    private var options: CaptureOptions = .defaultOptions
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
        
        let mainChannel = MainChannel(frameCaptureModuleInput: frameCaptureModuleInput, captureType: options.captureType)
        self.mainChannel = mainChannel
        completion(.success(mainChannel))
    }
    
    func openStream(input: [APIValue], _ completion: @escaping (Result<Void, APIError>) -> Void) {
        options = .init(apiValue: input.first) ?? .defaultOptions
        
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
}

private extension PhotoCapturePushStreamAPI {
    func retrieveBase64JPEG(into: @escaping (Result<[APIValue], APIError>) -> Void) {
        frameCaptureModuleInput?.setCaptureFrameHandler(handler: {
            switch $0 {
            case .success(let buffer):
                guard let jpegData = buffer.asUIImage?.jpegData(compressionQuality: 1.0) else {
                    into(.failure(.init(code: CameraFrameCapture.FrameCaptureError.frameCaptureFailure(nil).code)))
                    return
                }
                into(.success([.string("data:image/jpeg;base64," + jpegData.base64EncodedString())]))
            case .failure(let error):
                into(.failure(.init(code: error.code)))
            }
        }, isContinuous: true)
    }
    
    func retrieveBGRAFrame(into: @escaping (Result<[APIValue], APIError>) -> Void,
                           bufferProcessing: @escaping (CVImageBuffer) -> UnsafeMutableRawPointer?) {
        frameCaptureModuleInput?.setCaptureFrameHandler(handler: {
            switch $0 {
            case .success(let imageBuffer):
                guard let buffer = bufferProcessing(imageBuffer) else {
                    into(.failure(.init(code: CameraFrameCapture
                                            .FrameCaptureError
                                            .frameCaptureFailure(nil)
                                            .code
                                       )))
                    return
                }
                
                let data = Data(bytesNoCopy: buffer,
                                count: imageBuffer.byteCount,
                                deallocator: .free)
                
                into(.success([.bytes(data),
                               .number(Double(imageBuffer.rgba8888Width)),
                               .number(Double(imageBuffer.height))]))
                
            case .failure(let error):
                into(.failure(.init(code: error.code)))
            }
        }, isContinuous: true)
    }
}

private extension PhotoCapturePushStreamAPI {
    final class MainChannel: PushStreamChannel {
        private let frameCaptureModuleInput: CameraFrameCaptureModuleInput
        private let captureType: PhotoCaptureType
        private var dataListener: PushStreamChannelDataListener?
        
        init(frameCaptureModuleInput: CameraFrameCaptureModuleInput,
             captureType: PhotoCaptureType) {
            self.frameCaptureModuleInput = frameCaptureModuleInput
            self.captureType = captureType
        }
        
        func setDataListener(_ listener: @escaping PushStreamChannelDataListener) {
            dataListener = listener
            switch captureType {
            case .jpegBase64:
                beginRetrievingJPEGBase64()
            case .rgba:
                beginRetrievingBGRAFrames(bufferProcessing: { $0.copyBGRAToRGBA() })
            case .bgra:
                beginRetrievingBGRAFrames(bufferProcessing: { $0.copyBGRABuffer() })
            }
        }
        
        func handlePeerData(_ data: Data) {
            
        }
        
        func close() {
            
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
            frameCaptureModuleInput.setCaptureFrameHandler(handler: { [weak self] in
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
                    
                    self?.dataListener?(.from(intValue: imageBuffer.rgba8888Width), false)
                    self?.dataListener?(.from(intValue: imageBuffer.height), false)
                    self?.dataListener?(data, true)
                case .failure(let error):
//                    into(.failure(.init(code: error.code)))
                    break
                }
            }, isContinuous: true)
        }
        
    }
}
