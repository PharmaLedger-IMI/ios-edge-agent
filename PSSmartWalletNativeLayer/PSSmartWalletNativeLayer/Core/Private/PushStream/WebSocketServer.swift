//
//  WebSocketServer.swift
//  PSSmartWalletNativeLayer
//
//  Created by Costin Andronache on 22.06.2022.
//

import Foundation
import Network

final class WebSocketServer {
    let port: NWEndpoint.Port
    private let listener: NWListener
    private let parameters: NWParameters

    private var connections: [WebSocketConnection] = []
    var newConnectionInitializedHandler: ((WebSocketConnection, Data) -> Void)?
    
    var wsURL: String {
        "ws://localhost:\(port)"
    }
    
    init(portNumber: UInt16) {
        self.port = NWEndpoint.Port(rawValue: portNumber)!
        parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        listener = try! NWListener(using: parameters, on: port)
    }

    func start() throws {
        print("Server starting...")
        listener.stateUpdateHandler = self.stateDidChange(to:)
        listener.newConnectionHandler = self.didAccept(nwConnection:)
        listener.start(queue: .main)
    }

    func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            print("Server ready.")
        case .failed(let error):
            print("Server failure, error: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func didAccept(nwConnection: NWConnection) {
        let connection = WebSocketConnection(nwConnection: nwConnection)
        connection.didStopCallback = { [weak self] err in
            if let err = err {
                print(err)
            }
            self?.connectionDidStop(connection)
        }
        
        connection.didReceive = { [weak self, weak connection] data in
            guard let connection = connection else {
                return
            }
            self?.newConnectionInitializedHandler?(connection, data)
        }
        
        connections.append(connection)
        connection.start()
    }

    private func connectionDidStop(_ connection: WebSocketConnection) {
        
    }

    private func stop() {
        self.listener.stateUpdateHandler = nil
        self.listener.newConnectionHandler = nil
        self.listener.cancel()
    }
}
