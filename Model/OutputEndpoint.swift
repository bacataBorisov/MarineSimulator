import Foundation

enum NetworkTransport: String, Codable, CaseIterable, Identifiable {
    case udp
    case tcp

    var id: String { rawValue }
}

struct OutputEndpoint: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String        // unicast fallback IP; used when isBroadcast == false
    var port: UInt16
    var transport: NetworkTransport
    var isEnabled: Bool
    var isBroadcast: Bool   // UDP-only; sends to all subnet broadcast addresses

    /// The address actually used when sending.
    /// Returns "255.255.255.255" in broadcast mode, otherwise `host`.
    var effectiveHost: String { isBroadcast ? "255.255.255.255" : host }

    init(
        id: UUID = UUID(),
        name: String = "Primary Output",
        host: String,
        port: UInt16,
        transport: NetworkTransport = .udp,
        isEnabled: Bool = true,
        isBroadcast: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.transport = transport
        self.isEnabled = isEnabled
        self.isBroadcast = isBroadcast
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, transport, isEnabled, isBroadcast
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,             forKey: .id)
        name      = try c.decode(String.self,           forKey: .name)
        let rawHost = try c.decode(String.self,         forKey: .host)
        port      = try c.decode(UInt16.self,           forKey: .port)
        transport = try c.decode(NetworkTransport.self, forKey: .transport)
        isEnabled = try c.decode(Bool.self,             forKey: .isEnabled)

        if let stored = try c.decodeIfPresent(Bool.self, forKey: .isBroadcast) {
            // New format: isBroadcast is explicit in JSON.
            isBroadcast = stored
            host = rawHost
        } else {
            // Migrate old saves that stored "255.255.255.255" as the host.
            isBroadcast = rawHost == "255.255.255.255"
            host = isBroadcast ? "127.0.0.1" : rawHost
        }
    }
}

enum TransportStatusLevel: String {
    case idle
    case connected
    case warning
    case error
}

struct OutputEndpointStatus {
    var endpointID: UUID
    var level: TransportStatusLevel
    var message: String
    var updatedAt: Date = .now
}

struct TransportHistoryEvent: Identifiable {
    enum Category: String {
        case transport
        case lifecycle
        case fault
    }

    var id: UUID = UUID()
    var endpointID: UUID?
    var level: TransportStatusLevel
    var category: Category
    var message: String
    var timestamp: Date = .now
}
