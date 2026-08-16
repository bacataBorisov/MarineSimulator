//
//  UDPClient.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//
//  Uses a single POSIX SOCK_DGRAM socket with SO_BROADCAST.
//
//  Broadcast mode sends **once** on the preferred LAN interface (default-route /
//  en0, never link-local 169.254). Sending on every IFF_BROADCAST interface was
//  delivering duplicate NMEA to iPads when multiple interfaces were up.
//
//  NWConnection is not used here because it does not expose SO_BROADCAST.

import Foundation
import Network   // NWError — keeps the same completion type as TCPClient
import Darwin

final class UDPClient {
    private let queue = DispatchQueue(label: "udp.client.queue")
    private let fd: Int32
    private var reportedErrors: Set<String> = []
    /// Logged once so Configuration / Xcode show which iface+bcast is used.
    private var didLogBroadcastTarget = false

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

        let host = endpoint.effectiveHost
        let port = endpoint.port
        let key  = "\(host):\(port)"

        queue.async {
            if host == "255.255.255.255" {
                self.sendBroadcastOnce(data: data, port: port, key: key,
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
        queue.async {
            self.reportedErrors.removeAll()
            self.didLogBroadcastTarget = false
        }
    }

    // MARK: - Private helpers

    private struct BroadcastCandidate {
        let name: String
        let ifIndex: UInt32
        let unicast: in_addr
        let broadcast: in_addr
    }

    /// One directed broadcast on the preferred LAN interface (not every iface).
    private func sendBroadcastOnce(data: Data, port: UInt16, key: String,
                                   completion: @escaping (Result<Void, NWError>) -> Void) {
        guard let target = Self.preferredBroadcastCandidate() else {
            sendDirect(data: data, host: "255.255.255.255", port: port, key: key,
                       completion: completion)
            return
        }

        if !didLogBroadcastTarget {
            didLogBroadcastTarget = true
            let bcast = Self.ipv4String(target.broadcast)
            let uni = Self.ipv4String(target.unicast)
            print("UDP broadcast via \(target.name) (\(uni)) → \(bcast):\(port)  [single interface — avoids multi-homed duplicates]")
        }

        var bcast = sockaddr_in()
        bcast.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bcast.sin_family = sa_family_t(AF_INET)
        bcast.sin_port = port.bigEndian
        bcast.sin_addr = target.broadcast

        // Force the datagram out that interface (unbound sockets can otherwise mis-route).
        var ifIndex = target.ifIndex
        _ = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifIndex, socklen_t(MemoryLayout<UInt32>.size))
        defer {
            var zero: UInt32 = 0
            _ = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &zero, socklen_t(MemoryLayout<UInt32>.size))
        }

        let n = data.withUnsafeBytes { buf -> Int in
            guard let ptr = buf.baseAddress else { return -1 }
            return withUnsafePointer(to: bcast) { bp in
                bp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.sendto(fd, ptr, buf.count, 0, sa,
                                  socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        if n >= 0 {
            reportedErrors.remove(key)
            completion(.success(()))
        } else {
            let code = errno
            if reportedErrors.insert(key).inserted {
                print("UDP broadcast send error on \(target.name): errno \(code)")
            }
            completion(.failure(.posix(POSIXErrorCode(rawValue: code) ?? .EINVAL)))
        }
    }

    /// Prefer Wi‑Fi (`en0`), then any non–link-local IPv4; skip `169.254/16`.
    private static func preferredBroadcastCandidate() -> BroadcastCandidate? {
        let all = enumerateBroadcastCandidates()
        guard !all.isEmpty else { return nil }

        if let en0 = all.first(where: { $0.name == "en0" }) {
            return en0
        }
        if let lan = all.first(where: { !Self.isLinkLocal($0.unicast) }) {
            return lan
        }
        return all.first
    }

    private static func enumerateBroadcastCandidates() -> [BroadcastCandidate] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let head = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var result: [BroadcastCandidate] = []
        var cur: UnsafeMutablePointer<ifaddrs>? = head
        while let ifa = cur {
            defer { cur = ifa.pointee.ifa_next }

            let flags = Int32(ifa.pointee.ifa_flags)
            guard (flags & IFF_BROADCAST) != 0,
                  (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let addrSA = ifa.pointee.ifa_addr,
                  addrSA.pointee.sa_family == sa_family_t(AF_INET),
                  let bcastSA = ifa.pointee.ifa_dstaddr,
                  bcastSA.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            let name = String(cString: ifa.pointee.ifa_name)
            // Skip Apple peer-to-peer / AWDL — not the boat LAN.
            if name.hasPrefix("awdl") || name.hasPrefix("llw") { continue }

            let unicast = addrSA.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let broadcast = bcastSA.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let ifIndex = if_nametoindex(name)
            guard ifIndex != 0 else { continue }

            result.append(BroadcastCandidate(
                name: name,
                ifIndex: ifIndex,
                unicast: unicast,
                broadcast: broadcast
            ))
        }
        return result
    }

    private static func isLinkLocal(_ addr: in_addr) -> Bool {
        // 169.254.0.0/16 — first two octets in network byte order on little-endian: check bytes
        let s = addr.s_addr
        let b0 = UInt8(s & 0xff)
        let b1 = UInt8((s >> 8) & 0xff)
        return b0 == 169 && b1 == 254
    }

    private static func ipv4String(_ addr: in_addr) -> String {
        var copy = addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &copy, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
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
