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

    private struct PendingSend {
        let data: Data
        let completion: (Result<Void, NWError>) -> Void
    }

    private struct ConnectionEntry {
        var endpoint: OutputEndpoint
        var connection: NWConnection?
        var retryAfter: Date?
        var failureCount: Int = 0
        var lastReportedState: String?
        var isReady: Bool = false
        var pendingSends: [PendingSend] = []
    }

    private let queue = DispatchQueue(label: "tcp.client.queue")
    private var connections: [String: ConnectionEntry] = [:]
    var onStateChange: ((OutputEndpoint, StateUpdate) -> Void)?

    func send(_ message: String, to endpoint: OutputEndpoint, completion: @escaping (Result<Void, NWError>) -> Void) {
        guard endpoint.transport == .tcp else {
            completion(.success(()))
            return
        }

        guard let data = message.data(using: .utf8) else {
            completion(.failure(.posix(.EINVAL)))
            return
        }

        let key = "\(endpoint.host):\(endpoint.port)"
        queue.async {
            self.sendUnsafe(data: data, to: endpoint, key: key, completion: completion)
        }
    }

    func resetConnections() {
        queue.async {
            self.resetConnectionsUnsafe()
        }
    }

    // MARK: - Queue-confined (must run on `queue`)

    private func sendUnsafe(
        data: Data,
        to endpoint: OutputEndpoint,
        key: String,
        completion: @escaping (Result<Void, NWError>) -> Void
    ) {
        if let entry = connections[key], let retryAfter = entry.retryAfter, retryAfter > .now {
            completion(.failure(.posix(.ECONNABORTED)))
            return
        }

        _ = connectionUnsafe(for: endpoint, key: key)

        guard var entry = connections[key] else {
            completion(.failure(.posix(.EINVAL)))
            return
        }

        if entry.isReady, let connection = entry.connection {
            performSend(data: data, on: connection, key: key, completion: completion)
        } else {
            entry.pendingSends.append(PendingSend(data: data, completion: completion))
            connections[key] = entry
        }
    }

    private func connectionUnsafe(for endpoint: OutputEndpoint, key: String) -> NWConnection {
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
            existingEntry.isReady = false
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

    private func performSend(
        data: Data,
        on connection: NWConnection,
        key: String,
        completion: @escaping (Result<Void, NWError>) -> Void
    ) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else {
                completion(.failure(.posix(.ECONNABORTED)))
                return
            }
            self.queue.async {
                if let error {
                    self.handleSendError(error, for: key, completion: completion)
                } else {
                    completion(.success(()))
                }
            }
        })
    }

    private func handleSendError(
        _ error: NWError,
        for key: String,
        completion: @escaping (Result<Void, NWError>) -> Void
    ) {
        guard let entry = connections[key], let connection = entry.connection else {
            completion(.failure(error))
            return
        }

        switch connection.state {
        case .failed, .cancelled:
            removeConnectionUnsafe(for: key)
            completion(.failure(error))
        default:
            print("TCP send error to \(key) while connection is \(connection.state): \(error.debugDescription)")
            completion(.failure(error))
        }
    }

    private func flushPendingSends(for key: String) {
        guard var entry = connections[key], entry.isReady, let connection = entry.connection else {
            return
        }

        let pending = entry.pendingSends
        entry.pendingSends = []
        connections[key] = entry

        for send in pending {
            performSend(data: send.data, on: connection, key: key, completion: send.completion)
        }
    }

    private func failPendingSends(for key: String, error: NWError) {
        guard var entry = connections[key] else {
            return
        }

        let pending = entry.pendingSends
        entry.pendingSends = []
        connections[key] = entry

        for send in pending {
            send.completion(.failure(error))
        }
    }

    private func resetConnectionsUnsafe() {
        for entry in connections.values {
            entry.connection?.cancel()
            for send in entry.pendingSends {
                send.completion(.failure(.posix(.ECONNABORTED)))
            }
        }
        connections.removeAll()
    }

    private func removeConnectionUnsafe(for key: String) {
        guard let entry = connections.removeValue(forKey: key) else {
            return
        }
        for send in entry.pendingSends {
            send.completion(.failure(.posix(.ECONNABORTED)))
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
            entry.isReady = false
            connections[key] = entry
            notify(endpoint: entry.endpoint, state: .connecting, key: key)
        case .waiting(let error):
            entry.isReady = false
            connections[key] = entry
            let message = error.debugDescription
            notify(endpoint: entry.endpoint, state: .waiting(message), key: key)
        case .ready:
            entry.retryAfter = nil
            entry.failureCount = 0
            entry.isReady = true
            connections[key] = entry
            notify(endpoint: entry.endpoint, state: .ready, key: key)
            flushPendingSends(for: key)
        case .failed(let error):
            entry.failureCount += 1
            let backoff = min(pow(2, Double(entry.failureCount - 1)), 8)
            let retryAfter = Date().addingTimeInterval(backoff)
            entry.retryAfter = retryAfter
            entry.isReady = false
            entry.connection = nil
            connections[key] = entry
            failPendingSends(for: key, error: error)
            notify(endpoint: entry.endpoint, state: .failed(error, retryAfter: retryAfter), key: key)
        case .cancelled:
            entry.isReady = false
            notify(endpoint: entry.endpoint, state: .cancelled, key: key)
            entry.connection = nil
            connections[key] = entry
            failPendingSends(for: key, error: .posix(.ECONNABORTED))
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
