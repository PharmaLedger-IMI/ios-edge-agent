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
        let dataPtr = UnsafeMutableBufferPointer<Int32>.allocate(capacity: 1)
        var data = Data()
        
        func updateData() {
            data.replaceSubrange(data.startIndex..<data.endIndex, with: .init(dataPtr))
        }
        
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
            var value: Int32 = 0;
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.25,
                                         repeats: true,
                                         block: { [weak self] _ in
                guard let welf = self else {
                    return
                }
                value += 1
                welf.dataPtr[0] = value
                welf.updateData()
                self?.dataListener?(welf.data)
            })
        }
    }
}
