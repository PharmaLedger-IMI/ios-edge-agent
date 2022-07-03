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
    static let defaultOptions = Self(captureType: .jpegBase64)
    
    init(captureType: PhotoCaptureType) {
        self.captureType = captureType
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
