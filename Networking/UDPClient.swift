//
//  UDPClient.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

import Foundation
import Network

class UDPClient {
    private let queue = DispatchQueue(label: "udp.client.queue")
    private var connections: [String: NWConnection] = [:]

    func send(_ message: String, to endpoint: OutputEndpoint) {
        guard endpoint.transport == .udp else {
            return
        }

        let key = "\(endpoint.host):\(endpoint.port)"
        let connection = connection(for: endpoint, key: key)

        guard let data = message.data(using: .utf8) else {
            print("Failed to encode message")
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("UDP send error to \(key): \(error)")
            }
        })
    }

    func resetConnections() {
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func connection(for endpoint: OutputEndpoint, key: String) -> NWConnection {
        if let existingConnection = connections[key] {
            return existingConnection
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port)!,
            using: .udp
        )
        connection.start(queue: queue)
        connections[key] = connection
        return connection
    }
}
