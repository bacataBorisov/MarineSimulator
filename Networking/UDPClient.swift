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
    private var reportedConnectionRefusals: Set<String> = []

    func send(_ message: String, to endpoint: OutputEndpoint, completion: @escaping (Result<Void, NWError>) -> Void) {
        guard endpoint.transport == .udp else {
            completion(.success(()))
            return
        }

        let key = "\(endpoint.host):\(endpoint.port)"
        let connection = connection(for: endpoint, key: key)

        guard let data = message.data(using: .utf8) else {
            print("Failed to encode message")
            completion(.failure(.posix(.EINVAL)))
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                if case .posix(.ECONNREFUSED) = error {
                    if self.reportedConnectionRefusals.insert(key).inserted {
                        print("UDP output refused at \(key). Start a listener on that endpoint or change the destination.")
                    }
                    completion(.failure(error))
                    return
                }

                print("UDP send error to \(key): \(error)")
                completion(.failure(error))
            } else {
                self.reportedConnectionRefusals.remove(key)
                completion(.success(()))
            }
        })
    }

    func resetConnections() {
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        reportedConnectionRefusals.removeAll()
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
