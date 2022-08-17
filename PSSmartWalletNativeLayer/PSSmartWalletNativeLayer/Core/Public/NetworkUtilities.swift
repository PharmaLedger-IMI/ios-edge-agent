//
//  NetworkUtilities.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 12/30/20.
//

import Foundation

public struct NetworkUtilities {
    public static func findFreePort() -> UInt16? {
        let serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD != 0 else {
            return nil
        }
        
        var address: sockaddr_in = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        address.sin_port = 0
        
        let ptr: UnsafePointer<sockaddr_in> = UnsafePointer<sockaddr_in>(&address)
        let rawPtr: UnsafePointer<sockaddr> = UnsafeRawPointer(ptr).bindMemory(to: sockaddr.self, capacity: MemoryLayout<sockaddr_in>.stride)
        let sizeWithPadding = socklen_t(MemoryLayout<sockaddr_in>.stride)
        guard bind(serverFD, rawPtr, sizeWithPadding) >= 0 else {
            return nil
        }
        
        let mutRawPtr: UnsafeMutablePointer<sockaddr> = UnsafeMutableRawPointer(mutating: ptr).bindMemory(to: sockaddr.self, capacity: MemoryLayout<sockaddr_in>.stride)
        
        var mutSize = sizeWithPadding
        let mutLengthPtr = UnsafeMutablePointer<socklen_t>(&mutSize)
        guard getsockname(serverFD, mutRawPtr, mutLengthPtr) >= 0 else {
            return nil
        }
        shutdown(serverFD, SHUT_RDWR)
        close(serverFD)
        
        if isBigEndian() {
            return address.sin_port
        } else {
            return address.sin_port.littleEndian
        }
    }
    
    public static func executeWhenUrlAvilable(url: URL, job: @escaping () -> Void) {
        Thread {
            while true {
                if let _ = try? Data(contentsOf: url) {
                    DispatchQueue.main.async(execute: job)
                    return
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }.start()
    }
    
    public static func isBigEndian() -> Bool {
        let randomNumber = 0x12345678
        if randomNumber == randomNumber.bigEndian {
            return true
        }
        return false
    }
}
