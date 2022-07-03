//
//  CameraFrameCaptureModule.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 15.01.2022.
//

import Foundation
import AVFoundation
import UIKit

final class CameraFrameCaptureModule: NSObject {
    private let videoCaptureInput: VideoCaptureSessionModuleInput
    private let exitHandler: VoidBlock?
    
    private let output = AVCaptureVideoDataOutput()
    private var photoCaptureCompletion: ((CVImageBuffer) -> Void)?
    private let pixelFormat: CameraFrameCapture.PixelFormat
    
    
    init(pixelFormat: CameraFrameCapture.PixelFormat,
        videoCaptureInput: VideoCaptureSessionModuleInput,
         exitHandler: VoidBlock?) {
        self.videoCaptureInput = videoCaptureInput
        self.exitHandler = exitHandler
        self.pixelFormat = pixelFormat
        super.init()
    }
    
    func finalizeInitialization() -> Result<Void, CameraFrameCapture.InitializationError> {
        guard output.supportsPixelFormat(pixelFormat) else {
            return .failure(.unsupportedPixelFormatError(pixelFormat))
        }
        output.videoSettings = pixelFormat.asSettingsDictionary
        
        switch videoCaptureInput.addOutput(output) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(.cameraModuleFunctionalityError(error))
        }
    }
}

extension CameraFrameCaptureModule: CameraFrameCaptureModuleInput {
    func cancelFrameCapture() {
        videoCaptureInput.stopCapture()
        exitHandler?()
    }
    
    func setCaptureFrameHandler(handler: @escaping (Result<CVImageBuffer, CameraFrameCapture.FrameCaptureError>) -> Void,
                                isContinuous: Bool) {
        output.setSampleBufferDelegate(self, queue: .main)
        photoCaptureCompletion = { [weak self] in
            if !isContinuous {
                self?.output.setSampleBufferDelegate(nil, queue: nil)
            }
            handler(.success($0))
        }
    }
}

extension CameraFrameCaptureModule: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        output.connection(with: .video)?.videoOrientation = .portrait
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        photoCaptureCompletion?(imageBuffer)
    }
}

private extension CameraFrameCapture.PixelFormat {
    var asSettingsDictionary: [String: Any] {
        switch self {
        case .BGRA32:
            return [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        case .defaultDeviceFormat:
            return [:]
        }
    }
}

private extension AVCaptureVideoDataOutput {
    func supportsPixelFormat(_ pixelFormat: CameraFrameCapture.PixelFormat) -> Bool {
        switch pixelFormat {
        case .BGRA32:
            return availableVideoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA)
        case .defaultDeviceFormat:
            return true
        }
    }
}
