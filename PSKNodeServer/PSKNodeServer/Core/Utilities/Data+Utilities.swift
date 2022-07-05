//
//  Data+Utilities.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 03.07.2022.
//

import Foundation

extension Data {
    static func from<T>(value: T) -> Data {
        withUnsafePointer(to: value, { ptr in
            return Data(bytes: .init(ptr), count: MemoryLayout<T>.stride)
        })
    }
}
