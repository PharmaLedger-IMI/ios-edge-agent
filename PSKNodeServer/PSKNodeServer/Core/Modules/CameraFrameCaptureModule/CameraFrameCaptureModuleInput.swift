//
//  CameraFrameCaptureModuleInput.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 18.01.2022.
//

import Foundation
import AVFoundation
import UIKit

enum CameraFrameCapture {
    enum InitializationError: Swift.Error {
        case cameraModuleInitializationError(VideoCaptureSession.InitializationError)
        case cameraModuleFunctionalityError(VideoCaptureSession.AddOutputFailReason)
        case unsupportedPixelFormatError(PixelFormat)
    }
    
    enum FrameCaptureError: Swift.Error {
        case frameCaptureFailure(Swift.Error?)
    }
    
    enum PixelFormat {
        case BGRA32
        case defaultDeviceFormat
    }
    
    typealias CapturedFrameHandler = (Result<CVImageBuffer, FrameCaptureError>) -> Void
    typealias InitializationCompletion = (Result<Void, Error>) -> Void
}

protocol CameraFrameCaptureModuleInput {
    func cancelFrameCapture()
    func setCaptureFrameHandler(handler: @escaping CameraFrameCapture.CapturedFrameHandler,
                                isContinuous: Bool)
}
