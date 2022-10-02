//
//  WebSocketServer.swift
//  PSSmartWalletNativeLayer
//
//  Created by Costin Andronache on 22.06.2022.
//

import Foundation
import Network
import UIKit

final class WebSocketServer {
    private var port: NWEndpoint.Port?
    private var listener: NWListener?
    private var parameters: NWParameters?

    private var connections: [WebSocketConnection] = []
    var newConnectionInitializedHandler: ((WebSocketConnection, Data) -> Void)?
    
    var wsURL: String {
        "ws://localhost:\(port!.rawValue)"
    }
    
    init() {
        setupBackgroundListeners()
    }

    func start() throws {
        print("Server starting...")
        let portNumber = NetworkUtilities.findFreePort()!
        let port = NWEndpoint.Port(rawValue: portNumber)!
        self.port = port
        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        self.parameters = parameters
        listener = try NWListener(using: parameters, on: port)
        listener?.stateUpdateHandler = self.stateDidChange(to:)
        listener?.newConnectionHandler = self.didAccept(nwConnection:)
        listener?.start(queue: .main)
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
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
    }
    
    private func restartServerOnForeground() {
        print("Restarting WEBSOCKET SERVER ON FOREGROUND")
        stop()
        connections.forEach({ $0.stop() })
        do {
            try start()
        } catch let error {
            print("FOREGROUND WEBSOCKET RESTART ERROR: \(error)")
        }
    }
    
    private func setupBackgroundListeners() {
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main, using: { (_) in
                self.restartServerOnForeground()
            })
        } else {
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { (_) in
                self.restartServerOnForeground()
            })
        }
    }
}
