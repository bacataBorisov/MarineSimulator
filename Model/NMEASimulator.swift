//
//  NMEASimulator.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//


import Foundation
import Observation
import Network

@Observable
class NMEASimulator {
    var speed: Double = 0.0
    var depth: Double = 0.0
    let ip = "192.168.1.10"
    let port: UInt16 = 10110

    func sendNMEA() {
        let sentence = buildNMEASentence()
        sendUDPPacket(sentence)
    }

    private func buildNMEASentence() -> String {
        let sentence = "$VWVHW,,T,,M,\(String(format: "%.1f", speed)),N,,K"
        return addChecksum(to: sentence)
    }

    private func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }

    private func sendUDPPacket(_ sentence: String) {
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!, using: .udp)

        connection.start(queue: .global())
        let data = sentence.data(using: .utf8)!

        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Send error: \(error)")
            } else {
                print("✅ Sent: \(sentence.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            connection.cancel()
        }))
    }
}