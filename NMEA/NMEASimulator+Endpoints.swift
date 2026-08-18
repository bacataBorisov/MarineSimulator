import Foundation

extension NMEASimulator {

    // MARK: - Output endpoints

    func addOutputEndpoint() {
        outputEndpoints.append(
            OutputEndpoint(
                name: "Output \(outputEndpoints.count + 1)",
                host: ip,
                port: port,
                transport: .udp,
                isEnabled: true
            )
        )
    }

    func removeOutputEndpoint(id: OutputEndpoint.ID) {
        guard let index = outputEndpoints.firstIndex(where: { $0.id == id }) else {
            return
        }

        if index == 0 {
            return
        }

        outputEndpoints.remove(at: index)
        endpointStatuses.removeValue(forKey: id)
        if latestTransportStatus?.endpointID == id {
            latestTransportStatus = outputEndpoints.compactMap { endpointStatuses[$0.id] }.last
        }
    }

    func transportStatus(for endpointID: UUID) -> OutputEndpointStatus? {
        endpointStatuses[endpointID]
    }

    func clearTransportHistory() {
        transportHistory.removeAll()
    }

    func enabledOutputEndpoints() -> [OutputEndpoint] {
        if Thread.isMainThread {
            syncPrimaryOutputEndpoint()
            resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting()
        }
        return outputEndpoints.filter(\.isEnabled)
    }

    func send(_ sentence: String, to endpoint: OutputEndpoint) {
        transportManager.send(sentence, to: endpoint)
    }

    func recordTransportStatus(_ status: OutputEndpointStatus) {
        let previousStatus = endpointStatuses[status.endpointID]
        let statusChanged = previousStatus?.level != status.level || previousStatus?.message != status.message
        guard statusChanged else {
            return
        }

        endpointStatuses[status.endpointID] = status

        // Update the top-bar indicator:
        //   • Always update for the same endpoint so errors can recover to connected.
        //   • For a different endpoint, surface errors/warnings over idle/connected.
        if latestTransportStatus == nil
            || status.endpointID == latestTransportStatus?.endpointID
            || status.level == .error
            || status.level == .warning {
            latestTransportStatus = status
        }

        appendHistoryEvent(
            endpointID: status.endpointID,
            level: status.level,
            category: .transport,
            message: status.message,
            timestamp: status.updatedAt
        )
    }

    func syncPrimaryOutputEndpoint() {
        guard !isSynchronizingEndpoints else {
            return
        }

        isSynchronizingEndpoints = true
        defer { isSynchronizingEndpoints = false }

        if outputEndpoints.isEmpty {
            outputEndpoints = [OutputEndpoint(host: ip, port: port)]
            return
        }

        outputEndpoints[0].host = ip
        outputEndpoints[0].isBroadcast = isBroadcast
        outputEndpoints[0].port = port
    }

    func normalizeOutputEndpoints() {
        guard !isSynchronizingEndpoints else {
            return
        }

        isSynchronizingEndpoints = true
        defer { isSynchronizingEndpoints = false }

        if outputEndpoints.isEmpty {
            outputEndpoints = [OutputEndpoint(host: ip, port: port)]
        }

        outputEndpoints[0].name = outputEndpoints[0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Primary Output"
            : outputEndpoints[0].name
        outputEndpoints[0].host = outputEndpoints[0].host
        outputEndpoints[0].port = outputEndpoints[0].port

        // Broadcast is UDP-only. Auto-clear an invalid persisted state so the
        // toggle is never left ON-and-disabled with no way for the user to fix it.
        if outputEndpoints[0].transport == .tcp && outputEndpoints[0].isBroadcast {
            outputEndpoints[0].isBroadcast = false
        }

        if ip != outputEndpoints[0].host {
            ip = outputEndpoints[0].host
        }
        if isBroadcast != outputEndpoints[0].isBroadcast {
            isBroadcast = outputEndpoints[0].isBroadcast
        }
        if port != outputEndpoints[0].port {
            port = outputEndpoints[0].port
        }
    }

    func resetTransportConnections() {
        transportManager.resetConnections()
    }

    func resetTransportConnectionsIfTransmitting() {
        transportManager.resetConnectionsIfTransmitting(isTransmitting: isTransmitting)
    }

    func resetTransportConnectionsIfEndpointTargetsChanged(from oldEndpoints: [OutputEndpoint], to newEndpoints: [OutputEndpoint]) {
        transportManager.resetConnectionsIfEndpointTargetsChanged(from: oldEndpoints, to: newEndpoints, isTransmitting: isTransmitting)
    }

    func resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting() {
        transportManager.syncEndpointSignatures(from: outputEndpoints, isTransmitting: isTransmitting)
    }

    func refreshEndpointConnectionSignatures(from endpoints: [OutputEndpoint]? = nil) {
        transportManager.refreshEndpointConnectionSignatures(from: endpoints ?? outputEndpoints)
    }
}

extension NMEASimulator: TransportManagerDelegate {
    func transportManager(_ manager: TransportManager, didUpdateStatus status: OutputEndpointStatus) {
        if Thread.isMainThread {
            recordTransportStatus(status)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.recordTransportStatus(status)
            }
        }
    }

    func transportManager(_ manager: TransportManager, didEmitHistoryEvent endpointID: UUID?, level: TransportStatusLevel, category: TransportHistoryEvent.Category, message: String, timestamp: Date) {
        if Thread.isMainThread {
            appendHistoryEvent(endpointID: endpointID, level: level, category: category, message: message, timestamp: timestamp)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendHistoryEvent(endpointID: endpointID, level: level, category: category, message: message, timestamp: timestamp)
            }
        }
    }
}
