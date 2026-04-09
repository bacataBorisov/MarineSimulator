import Foundation
import Network

final class TCPClient {
    enum StateUpdate {
        case connecting
        case ready
        case waiting(String)
        case failed(NWError, retryAfter: Date)
        case cancelled
    }

    private struct ConnectionEntry {
        var endpoint: OutputEndpoint
        var connection: NWConnection?
        var retryAfter: Date?
        var failureCount: Int = 0
        var lastReportedState: String?
    }

    private let queue = DispatchQueue(label: "tcp.client.queue")
    private var connections: [String: ConnectionEntry] = [:]
    var onStateChange: ((OutputEndpoint, StateUpdate) -> Void)?

    func send(_ message: String, to endpoint: OutputEndpoint, completion: @escaping (Result<Void, NWError>) -> Void) {
        guard endpoint.transport == .tcp else {
            completion(.success(()))
            return
        }

        let key = "\(endpoint.host):\(endpoint.port)"
        if let entry = connections[key], let retryAfter = entry.retryAfter, retryAfter > .now {
            completion(.failure(.posix(.ECONNABORTED)))
            return
        }

        let connection = connection(for: endpoint, key: key)

        guard let data = message.data(using: .utf8) else {
            completion(.failure(.posix(.EINVAL)))
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.removeConnection(for: key)
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    func resetConnections() {
        for entry in connections.values {
            entry.connection?.cancel()
        }
        connections.removeAll()
    }

    private func connection(for endpoint: OutputEndpoint, key: String) -> NWConnection {
        if let existingConnection = connections[key]?.connection {
            return existingConnection
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port)!,
            using: .tcp
        )
        if var existingEntry = connections[key] {
            existingEntry.endpoint = endpoint
            existingEntry.connection = connection
            connections[key] = existingEntry
        } else {
            connections[key] = ConnectionEntry(endpoint: endpoint, connection: connection)
        }
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleStateUpdate(state, for: key)
        }
        connection.start(queue: queue)
        notify(endpoint: endpoint, state: .connecting, key: key)
        return connection
    }

    private func removeConnection(for key: String) {
        guard let entry = connections.removeValue(forKey: key) else {
            return
        }
        entry.connection?.cancel()
    }

    private func handleStateUpdate(_ state: NWConnection.State, for key: String) {
        guard var entry = connections[key] else {
            return
        }

        switch state {
        case .setup:
            return
        case .preparing:
            notify(endpoint: entry.endpoint, state: .connecting, key: key)
        case .waiting(let error):
            let message = error.debugDescription
            notify(endpoint: entry.endpoint, state: .waiting(message), key: key)
        case .ready:
            entry.retryAfter = nil
            entry.failureCount = 0
            connections[key] = entry
            notify(endpoint: entry.endpoint, state: .ready, key: key)
        case .failed(let error):
            entry.failureCount += 1
            let backoff = min(pow(2, Double(entry.failureCount - 1)), 8)
            let retryAfter = Date().addingTimeInterval(backoff)
            entry.retryAfter = retryAfter
            entry.connection = nil
            connections[key] = entry
            notify(endpoint: entry.endpoint, state: .failed(error, retryAfter: retryAfter), key: key)
        case .cancelled:
            notify(endpoint: entry.endpoint, state: .cancelled, key: key)
            entry.connection = nil
            connections[key] = entry
        @unknown default:
            return
        }
    }

    private func notify(endpoint: OutputEndpoint, state: StateUpdate, key: String) {
        let stateDescription: String = {
            switch state {
            case .connecting:
                return "connecting"
            case .ready:
                return "ready"
            case .waiting(let message):
                return "waiting:\(message)"
            case .failed(let error, let retryAfter):
                return "failed:\(error.debugDescription):\(retryAfter.timeIntervalSinceReferenceDate)"
            case .cancelled:
                return "cancelled"
            }
        }()

        if var entry = connections[key] {
            if entry.lastReportedState == stateDescription {
                return
            }
            entry.lastReportedState = stateDescription
            connections[key] = entry
        }

        onStateChange?(endpoint, state)
    }
}
