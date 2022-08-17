//
//  WebSocketConnection.swift
//  PSSmartWalletNativeLayer
//
//  Created by Costin Andronache on 22.06.2022.
//

import Foundation
import Network

final class WebSocketConnection {
    private let connection: NWConnection
    private let dataContext = NWConnection.ContentContext(identifier: "dataContext", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
    private let textContext = NWConnection.ContentContext(identifier: "textContext", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
    
    var apiName: String = "unknown"
    var channelName: String = "unknown"
    var didStopCallback: ((Swift.Error?) -> Void)? = nil
    var didReceive: ((Data) -> ())? = nil

    init(nwConnection: NWConnection) {
        connection = nwConnection
    }
    
    func start() {
        connection.stateUpdateHandler = self.stateDidChange(to:)
        setupReceive()
        connection.start(queue: .main)
    }

    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .waiting(let error):
            print("connection - waiting \(error)")
            connectionDidFail(error: error)
        case .ready:
            print("connection \(apiName) - \(channelName) ready")
        case .failed(let error):
            print("connection - failed \(error)")
            connectionDidFail(error: error)
        case .setup:
            print("connection - setup")
        case .preparing:
            print("connection - preparing")
        case .cancelled:
            print("connection - cancelled")
        @unknown default:
            break
        }
    }

    private func setupReceive() {
        connection.receiveMessage() { [weak self] (data, context, isComplete, error) in
            if let data = data, let context = context, !data.isEmpty {
                self?.handleMessage(data: data, context: context)
            }
            if let error = error {
                self?.connectionDidFail(error: error)
            } else {
                self?.setupReceive()
            }
        }
    }
    
    func handleMessage(data: Data, context: NWConnection.ContentContext) {
        didReceive?(data)
    }

    func send(data: Data, isComplete: Bool) {
        connection.send(content: data,
                        contentContext: dataContext,
                        isComplete: isComplete,
                        completion: .contentProcessed( { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
        }))
    }
    
    func send(ascii: String, isComplete: Bool) {
        connection.send(content: ascii.data(using: .ascii)!,
                        contentContext: textContext,
                        isComplete: isComplete,
                        completion: .contentProcessed( { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
        }))
    }

    func stop() {
    }

    private func connectionDidFail(error: Swift.Error) {
        stop(error: error)
    }

    private func connectionDidEnd() {
        stop(error: nil)
    }

    private func stop(error: Swift.Error?) {
        connection.stateUpdateHandler = nil
        connection.cancel()
        if let didStopCallback = didStopCallback {
            self.didStopCallback = nil
            didStopCallback(error)
        }
        didReceive = nil
    }
}
