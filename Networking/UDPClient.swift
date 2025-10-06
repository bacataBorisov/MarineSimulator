//
//  UDPClient.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//


//
//  UDPClient.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

import Foundation
import Network

class UDPClient {
    private let ip: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "udp.client.queue")

    init(ip: String, port: UInt16) {
        self.ip = ip
        self.port = port
    }

    func send(_ message: String) {
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        connection.start(queue: queue)

        guard let data = message.data(using: .utf8) else {
            print("❌ Failed to encode message")
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("❌ Send error: \(error)")
            } else {
                print("✅ Sent: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            connection.cancel()
        })
    }
}