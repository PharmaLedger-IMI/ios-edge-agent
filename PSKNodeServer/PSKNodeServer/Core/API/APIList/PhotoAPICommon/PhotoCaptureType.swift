//
//  PhotoCaptureType.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 03.07.2022.
//

import Foundation
import PSSmartWalletNativeLayer

enum PhotoCaptureType: String, Decodable {
    case jpegBase64
    case rgba
    case bgra
}

struct CaptureOptions: Decodable {
    let captureType: PhotoCaptureType
    let fps: Int
    static let defaultOptions = Self(captureType: .jpegBase64)
    
    init(captureType: PhotoCaptureType,
         fps: Int = 10) {
        self.captureType = captureType
        self.fps = fps
    }
    
    init?(apiValue: APIValue?) {
        guard case .string(let json) = apiValue,
              let data = json.data(using: .ascii) else {
                  return nil
              }
        
        do {
            let result = try JSONDecoder().decode(Self.self, from: data)
            self = result
        } catch let error {
            print("Error: \(error)")
            return nil
        }
    }
}
