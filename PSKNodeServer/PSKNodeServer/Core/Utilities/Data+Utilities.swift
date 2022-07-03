//
//  Data+Utilities.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 03.07.2022.
//

import Foundation

extension Data {
    static func from(intValue: Int) -> Data {
        withUnsafePointer(to: intValue, { ptr in
            return Data(bytes: .init(ptr), count: MemoryLayout<Int>.stride)
        })
    }
}
