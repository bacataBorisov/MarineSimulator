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
