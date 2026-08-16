import Foundation
import Network

/// Delegate protocol for receiving transport status updates.
/// All delegate methods are called on the main thread.
protocol TransportManagerDelegate: AnyObject {
    func transportManager(_ manager: TransportManager, didUpdateStatus status: OutputEndpointStatus)
    func transportManager(_ manager: TransportManager, didEmitHistoryEvent endpointID: UUID?, level: TransportStatusLevel, category: TransportHistoryEvent.Category, message: String, timestamp: Date)
}

/// Owns the UDP and TCP transport clients and all connection-management logic.
/// Extracted from NMEASimulator (Phase 4 of the refactoring plan).
final class TransportManager {

    private let udpClient = UDPClient()
    private let tcpClient = TCPClient()

    /// Tracks per-endpoint connection signatures to detect when targets change
    /// and connections need to be reset.
    private var endpointConnectionSignatures: [UUID: String] = [:]

    /// Weak delegate — all callbacks dispatched to main thread.
    weak var delegate: TransportManagerDelegate?

    init() {
        tcpClient.onStateChange = { [weak self] endpoint, state in
            self?.handleTCPStateUpdate(state, for: endpoint)
        }
    }

    // MARK: - Sending

    func send(_ sentence: String, to endpoint: OutputEndpoint) {
        switch endpoint.transport {
        case .udp:
            udpClient.send(sentence, to: endpoint) { [weak self] result in
                self?.handleTransportResult(result, for: endpoint)
            }
        case .tcp:
            tcpClient.send(sentence, to: endpoint) { [weak self] result in
                self?.handleTransportResult(result, for: endpoint)
            }
        }
    }

    // MARK: - Connection Management

    func resetConnections() {
        udpClient.resetConnections()
        tcpClient.resetConnections()
    }

    func resetConnectionsIfTransmitting(isTransmitting: Bool) {
        guard isTransmitting else { return }
        resetConnections()
        refreshEndpointConnectionSignatures()
    }

    func resetConnectionsIfEndpointTargetsChanged(
        from oldEndpoints: [OutputEndpoint],
        to newEndpoints: [OutputEndpoint],
        isTransmitting: Bool
    ) {
        guard isTransmitting else {
            refreshEndpointConnectionSignatures(from: newEndpoints)
            return
        }

        let oldByID = Dictionary(uniqueKeysWithValues: oldEndpoints.map { ($0.id, $0) })
        let connectionTargetChanged = newEndpoints.contains { endpoint in
            guard let previous = oldByID[endpoint.id] else {
                return false
            }
            return endpointConnectionSignature(for: previous) != endpointConnectionSignature(for: endpoint)
        }

        if connectionTargetChanged {
            resetConnections()
        }
        refreshEndpointConnectionSignatures(from: newEndpoints)
    }

    func syncEndpointSignatures(from endpoints: [OutputEndpoint], isTransmitting: Bool) {
        guard isTransmitting else {
            refreshEndpointConnectionSignatures(from: endpoints)
            return
        }

        var connectionTargetChanged = false
        for endpoint in endpoints {
            let signature = endpointConnectionSignature(for: endpoint)
            if endpointConnectionSignatures[endpoint.id] != signature {
                connectionTargetChanged = true
            }
            endpointConnectionSignatures[endpoint.id] = signature
        }

        let staleIDs = Set(endpointConnectionSignatures.keys).subtracting(endpoints.map(\.id))
        if !staleIDs.isEmpty {
            connectionTargetChanged = true
            for staleID in staleIDs {
                endpointConnectionSignatures.removeValue(forKey: staleID)
            }
        }

        if connectionTargetChanged {
            resetConnections()
        }
    }

    func clearSignatures() {
        endpointConnectionSignatures.removeAll()
    }

    func refreshEndpointConnectionSignatures(from endpoints: [OutputEndpoint]? = nil) {
        guard let endpoints else {
            // No-op when called without endpoints — caller should pass the array.
            return
        }
        endpointConnectionSignatures = Dictionary(
            uniqueKeysWithValues: endpoints.map { ($0.id, endpointConnectionSignature(for: $0)) }
        )
    }

    // MARK: - Private

    private func endpointConnectionSignature(for endpoint: OutputEndpoint) -> String {
        "\(endpoint.transport.rawValue)|\(endpoint.effectiveHost)|\(endpoint.port)|\(endpoint.isEnabled)"
    }

    private func handleTransportResult(_ result: Result<Void, NWError>, for endpoint: OutputEndpoint) {
        let status: OutputEndpointStatus
        switch result {
        case .success:
            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .connected,
                message: "\(endpoint.transport.rawValue.uppercased()) connected to \(endpoint.effectiveHost):\(endpoint.port)"
            )
        case .failure(let error):
            let level: TransportStatusLevel = {
                if case .posix(.ECONNREFUSED) = error {
                    return .warning
                }
                if case .posix(.ECONNABORTED) = error {
                    return .warning
                }
                return .error
            }()

            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: level,
                message: "\(endpoint.transport.rawValue.uppercased()) \(endpoint.effectiveHost):\(endpoint.port) - \(transportErrorSummary(error))"
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let delegate = self.delegate else { return }
            delegate.transportManager(self, didUpdateStatus: status)
        }
    }

    private func handleTCPStateUpdate(_ state: TCPClient.StateUpdate, for endpoint: OutputEndpoint) {
        let status: OutputEndpointStatus
        switch state {
        case .connecting:
            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .idle,
                message: "TCP connecting to \(endpoint.effectiveHost):\(endpoint.port)"
            )
        case .ready:
            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .connected,
                message: "TCP connected to \(endpoint.effectiveHost):\(endpoint.port)"
            )
        case .waiting:
            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .warning,
                message: "TCP waiting for \(endpoint.effectiveHost):\(endpoint.port)"
            )
        case .failed(let error, let retryAfter):
            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .error,
                message: "TCP \(endpoint.effectiveHost):\(endpoint.port) - \(transportErrorSummary(error)) (retry after \(retryAfter.formatted(date: .omitted, time: .standard)))"
            )
        case .cancelled:
            status = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .idle,
                message: "TCP \(endpoint.effectiveHost):\(endpoint.port) idle"
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let delegate = self.delegate else { return }
            delegate.transportManager(self, didUpdateStatus: status)
        }
    }

    private func transportErrorSummary(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            return "connection refused"
        case .posix(.ECONNABORTED):
            return "retry cooling down"
        case .posix(.ETIMEDOUT):
            return "timed out"
        default:
            return error.localizedDescription
        }
    }
}
