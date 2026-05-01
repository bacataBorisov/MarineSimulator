//
//  UDPClient.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//
//  Uses a single POSIX SOCK_DGRAM socket with SO_BROADCAST so the same send
//  path works for both unicast endpoints (e.g. 192.168.1.50) and the limited
//  broadcast address 255.255.255.255. NWConnection does not expose SO_BROADCAST,
//  which is why this file uses Darwin directly.

import Foundation
import Network   // NWError — keeps the same completion type as TCPClient
import Darwin

final class UDPClient {
    private let queue = DispatchQueue(label: "udp.client.queue")
    private let fd: Int32
    private var reportedErrors: Set<String> = []

    init() {
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        if sock >= 0 {
            var yes: Int32 = 1
            Darwin.setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes,
                              socklen_t(MemoryLayout<Int32>.size))
        }
        fd = sock
    }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
    }

    // MARK: - Send

    func send(_ message: String, to endpoint: OutputEndpoint,
              completion: @escaping (Result<Void, NWError>) -> Void) {
        guard endpoint.transport == .udp else {
            completion(.success(()))
            return
        }
        guard fd >= 0 else {
            completion(.failure(.posix(.EBADF)))
            return
        }
        guard let data = message.data(using: .utf8) else {
            completion(.failure(.posix(.EINVAL)))
            return
        }

        let host = endpoint.host
        let port = endpoint.port

        queue.async {
            var addr = sockaddr_in()
            addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port   = port.bigEndian
            addr.sin_addr.s_addr = Darwin.inet_addr(host)

            let sent = data.withUnsafeBytes { rawBuf -> Int in
                guard let ptr = rawBuf.baseAddress else { return -1 }
                return withUnsafePointer(to: addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        Darwin.sendto(self.fd, ptr, rawBuf.count, 0, sa,
                                      socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            let key = "\(host):\(port)"
            if sent < 0 {
                let code = errno
                if self.reportedErrors.insert(key).inserted {
                    if code == ECONNREFUSED {
                        print("UDP output refused at \(key). Start a listener on that endpoint or change the destination.")
                    } else {
                        print("UDP send error to \(key): errno \(code)")
                    }
                }
                let posixCode = POSIXErrorCode(rawValue: code) ?? .EINVAL
                completion(.failure(.posix(posixCode)))
            } else {
                self.reportedErrors.remove(key)
                completion(.success(()))
            }
        }
    }

    // MARK: - Reset

    /// Clears cached error state. The underlying socket stays open.
    func resetConnections() {
        queue.async { self.reportedErrors.removeAll() }
    }
}
