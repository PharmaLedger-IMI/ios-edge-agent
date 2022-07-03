//
//  PhotoCaptureStreamAPI.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 16.01.2022.
//

import PSSmartWalletNativeLayer
import CoreVideo

final class PhotoCaptureStreamAPI {
    typealias ViewControllerProvider = DataMatrixScanAPI.ViewControllerProvider
    private let frameCaptureModuleBuilder: CameraFrameCaptureModuleBuildable
    private var frameCaptureModuleInput: CameraFrameCaptureModuleInput?
        
    private var options: CaptureOptions = .defaultOptions
    init(frameCaptureModuleBuilder: CameraFrameCaptureModuleBuildable) {
        self.frameCaptureModuleBuilder = frameCaptureModuleBuilder
    }
}

extension PhotoCaptureStreamAPI: StreamAPIImplementation {
    func openStream(input: [APIValue], completion: @escaping (Result<Void, APIError>) -> Void) {
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
    
    func retrieveNext(input: [APIValue], into: @escaping (Result<[APIValue], APIError>) -> Void) {
        switch options.captureType {
        case .jpegBase64:
            retrieveBase64JPEG(into: into)
        case .bgra:
            retrieveBGRAFrame(into: into,
                              bufferProcessing: { $0.copyBGRABuffer() })
        case .rgba:
            retrieveBGRAFrame(into: into,
                              bufferProcessing: { $0.copyBGRAToRGBA() })
        }
    }
    
    func close() {
        frameCaptureModuleInput?.cancelFrameCapture()
    }
}

private extension PhotoCaptureStreamAPI {
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
        }, isContinuous: false)
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
        }, isContinuous: false)
    }
}

extension CameraFrameCapture.InitializationError {
    var code: String {
        switch self {
        case .cameraModuleFunctionalityError(let error):
            return error.code
        case .unsupportedPixelFormatError:
            return "ERR_UNSUPPORTED_PIXEL_FORMAT"
        case .cameraModuleInitializationError(let error):
            return error.code
        }
    }
}

extension CameraFrameCapture.FrameCaptureError {
    var code: String {
        switch self {
        case .frameCaptureFailure:
            return "ERR_PHOTO_CAPTURE_FAILURE"
        }
    }
}

