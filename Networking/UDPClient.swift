//
//  UDPClient.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//
//  Uses a single POSIX SOCK_DGRAM socket with SO_BROADCAST.
//
//  When the destination host is "255.255.255.255" the sender enumerates
//  active network interfaces via getifaddrs() and sends a directed broadcast
//  to every interface that has IFF_BROADCAST set (e.g. 192.168.1.255 for a
//  192.168.1.0/24 WiFi network).  This is more reliable than the limited
//  broadcast address on macOS because the kernel routing table is bypassed —
//  the packet is sent directly on each interface's subnet.
//
//  For any other destination the packet is sent with a normal sendto() call.
//  NWConnection is not used here because it does not expose SO_BROADCAST.

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
        let key  = "\(host):\(port)"

        queue.async {
            if host == "255.255.255.255" {
                self.sendBroadcastAllInterfaces(data: data, port: port, key: key,
                                                completion: completion)
            } else {
                self.sendDirect(data: data, host: host, port: port, key: key,
                                completion: completion)
            }
        }
    }

    // MARK: - Reset

    /// Clears cached error state. The underlying socket stays open.
    func resetConnections() {
        queue.async { self.reportedErrors.removeAll() }
    }

    // MARK: - Private helpers

    /// Enumerate every IPv4 interface that supports broadcast, send a directed
    /// broadcast to its subnet broadcast address.  Returns success if at least
    /// one interface succeeded, or falls back to a direct 255.255.255.255 send
    /// when no broadcast-capable interface is found.
    private func sendBroadcastAllInterfaces(data: Data, port: UInt16, key: String,
                                            completion: @escaping (Result<Void, NWError>) -> Void) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard Darwin.getifaddrs(&ifaddr) == 0, let head = ifaddr else {
            sendDirect(data: data, host: "255.255.255.255", port: port, key: key,
                       completion: completion)
            return
        }
        defer { Darwin.freeifaddrs(ifaddr) }

        var anySent = false
        var cur: UnsafeMutablePointer<ifaddrs>? = head
        while let ifa = cur {
            defer { cur = ifa.pointee.ifa_next }

            let flags = Int32(ifa.pointee.ifa_flags)
            // On macOS, the broadcast address is stored in ifa_dstaddr when
            // IFF_BROADCAST is set (ifa_broadaddr is a Linux-only alias).
            guard (flags & IFF_BROADCAST) != 0,
                  (flags & IFF_UP)        != 0,
                  (flags & IFF_LOOPBACK)  == 0,
                  let bcastSA = ifa.pointee.ifa_dstaddr,
                  bcastSA.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            // Copy the broadcast sockaddr_in and set the destination port.
            var bcast = bcastSA.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            bcast.sin_port = port.bigEndian

            let n = data.withUnsafeBytes { buf -> Int in
                guard let ptr = buf.baseAddress else { return -1 }
                return withUnsafePointer(to: bcast) { bp in
                    bp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        Darwin.sendto(fd, ptr, buf.count, 0, sa,
                                      socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if n >= 0 { anySent = true }
        }

        if anySent {
            reportedErrors.remove(key)
            completion(.success(()))
        } else {
            // No broadcast-capable interface found; try the raw limited broadcast.
            sendDirect(data: data, host: "255.255.255.255", port: port, key: key,
                       completion: completion)
        }
    }

    private func sendDirect(data: Data, host: String, port: UInt16, key: String,
                            completion: @escaping (Result<Void, NWError>) -> Void) {
        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        addr.sin_addr.s_addr = Darwin.inet_addr(host)

        let sent = data.withUnsafeBytes { rawBuf -> Int in
            guard let ptr = rawBuf.baseAddress else { return -1 }
            return withUnsafePointer(to: addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.sendto(fd, ptr, rawBuf.count, 0, sa,
                                  socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        if sent < 0 {
            let code = errno
            if reportedErrors.insert(key).inserted {
                if code == ECONNREFUSED {
                    print("UDP output refused at \(key). Start a listener on that endpoint or change the destination.")
                } else {
                    print("UDP send error to \(key): errno \(code)")
                }
            }
            completion(.failure(.posix(POSIXErrorCode(rawValue: code) ?? .EINVAL)))
        } else {
            reportedErrors.remove(key)
            completion(.success(()))
        }
    }
}
