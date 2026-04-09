import Foundation

enum NetworkTransport: String, Codable, CaseIterable, Identifiable {
    case udp
    case tcp

    var id: String { rawValue }
}

struct OutputEndpoint: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: UInt16
    var transport: NetworkTransport
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "Primary Output",
        host: String,
        port: UInt16,
        transport: NetworkTransport = .udp,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.transport = transport
        self.isEnabled = isEnabled
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
