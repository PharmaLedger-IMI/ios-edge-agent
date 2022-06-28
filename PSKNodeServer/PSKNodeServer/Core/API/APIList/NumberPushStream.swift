//
//  NumberPushStream.swift
//  PSKNodeServer
//
//  Created by Costin Andronache on 29.06.2022.
//

import Foundation
import PSSmartWalletNativeLayer

final class NumberPushStream: PushStreamAPIImplementation {
    private let channel = MainChannel()
    func openStream(_ completion: @escaping (Result<Void, APIError>) -> Void) {
        completion(.success(()))
    }
    
    func openChannel(named: String, completion: @escaping (Result<PushStreamChannel, APIError>) -> Void) {
        completion(.success(channel))
    }
}

private extension NumberPushStream {
    final class MainChannel: PushStreamChannel {
        var dataListener: ((Data) -> Void)?
        var timer: Timer?
        func setDataListener(_ listener: @escaping (Data) -> Void) {
            dataListener = listener
            launchNewStream()
        }
        
        func handlePeerData(_ data: Data) {
            print("Received data: \(String(data: data, encoding: .ascii))")
        }
        
        func close() {
            
        }
        
        func launchNewStream() {
            var value = 0;
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25,
                                         repeats: true,
                                         block: { [weak self] _ in
                value += 1
                self?.dataListener?("\(value)".data(using: .ascii)!)
            })
        }
    }
}
