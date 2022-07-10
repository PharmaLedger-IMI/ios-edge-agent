//
//  Int+Utilities.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 10.07.2022.
//

import Foundation

extension Int {
    var frameDuration: TimeInterval {
        1.0 / Double(self)
    }
}
