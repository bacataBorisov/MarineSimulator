import Foundation
import Testing
@testable import MarineSimulator

/// Locks primary/secondary endpoint sync after the `NMEASimulator+Endpoints` extract.
@Suite(.serialized)
struct EndpointsRegressionTests {

    @Test
    func addOutputEndpointCopiesPrimaryHostPortAndEnables() {
        let simulator = makeEndpointSimulator()
        simulator.ip = "10.0.0.8"
        simulator.port = 10110

        simulator.addOutputEndpoint()

        #expect(simulator.outputEndpoints.count == 2)
        #expect(simulator.outputEndpoints[1].host == "10.0.0.8")
        #expect(simulator.outputEndpoints[1].port == 10110)
        #expect(simulator.outputEndpoints[1].transport == .udp)
        #expect(simulator.outputEndpoints[1].isEnabled)
        #expect(simulator.outputEndpoints[1].name == "Output 2")
    }

    @Test
    func removeOutputEndpointIgnoresPrimaryAndDropsSecondaryStatus() {
        let simulator = makeEndpointSimulator()
        let primaryID = simulator.outputEndpoints[0].id
        simulator.addOutputEndpoint()
        let secondaryID = simulator.outputEndpoints[1].id
        simulator.recordTransportStatus(
            OutputEndpointStatus(endpointID: secondaryID, level: .idle, message: "UDP idle")
        )

        simulator.removeOutputEndpoint(id: primaryID)
        #expect(simulator.outputEndpoints.count == 2)
        #expect(simulator.outputEndpoints[0].id == primaryID)

        simulator.removeOutputEndpoint(id: secondaryID)
        #expect(simulator.outputEndpoints.count == 1)
        #expect(simulator.transportStatus(for: secondaryID) == nil)
    }

    @Test
    func syncPrimaryOutputEndpointWritesTopLevelFieldsOntoPrimary() {
        let simulator = makeEndpointSimulator()
        simulator.ip = "192.168.1.20"
        simulator.port = 2000
        simulator.isBroadcast = true

        simulator.syncPrimaryOutputEndpoint()

        #expect(simulator.outputEndpoints[0].host == "192.168.1.20")
        #expect(simulator.outputEndpoints[0].port == 2000)
        #expect(simulator.outputEndpoints[0].isBroadcast)
    }

    @Test
    func normalizeOutputEndpointsRestoresEmptyListAndClearsTcpBroadcast() {
        let simulator = makeEndpointSimulator()
        simulator.ip = "172.16.0.4"
        simulator.port = 4951
        simulator.outputEndpoints = []

        #expect(simulator.outputEndpoints.count == 1)
        #expect(simulator.outputEndpoints[0].host == "172.16.0.4")
        #expect(simulator.outputEndpoints[0].port == 4951)

        simulator.outputEndpoints[0].transport = .tcp
        simulator.outputEndpoints[0].isBroadcast = true
        simulator.normalizeOutputEndpoints()

        #expect(simulator.outputEndpoints[0].isBroadcast == false)
        #expect(simulator.isBroadcast == false)
    }

    @Test
    func normalizeOutputEndpointsMirrorsPrimaryHostPortBackToTopLevel() {
        let simulator = makeEndpointSimulator()
        simulator.outputEndpoints[0].host = "10.1.2.3"
        simulator.outputEndpoints[0].port = 9000
        simulator.normalizeOutputEndpoints()

        #expect(simulator.ip == "10.1.2.3")
        #expect(simulator.port == 9000)
    }

    @Test
    func enabledOutputEndpointsFiltersDisabledRows() {
        let simulator = makeEndpointSimulator()
        simulator.addOutputEndpoint()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.outputEndpoints[1].isEnabled = true

        let enabled = simulator.enabledOutputEndpoints()
        #expect(enabled.map(\.id) == [simulator.outputEndpoints[1].id])
    }

    @Test
    func recordTransportStatusSurfacesErrorsAndIgnoresDuplicateIdle() {
        let simulator = makeEndpointSimulator()
        let primary = simulator.outputEndpoints[0].id
        let secondary = UUID()
        let idle = OutputEndpointStatus(endpointID: primary, level: .idle, message: "idle")
        simulator.recordTransportStatus(idle)
        #expect(simulator.latestTransportStatus?.endpointID == primary)

        simulator.recordTransportStatus(idle)
        #expect(simulator.transportHistory.filter { $0.endpointID == primary }.count == 1)

        let error = OutputEndpointStatus(endpointID: secondary, level: .error, message: "TCP failed")
        simulator.recordTransportStatus(error)
        #expect(simulator.latestTransportStatus?.endpointID == secondary)
        #expect(simulator.latestTransportStatus?.level == .error)
    }

    @Test
    func clearTransportHistoryEmptiesRecords() {
        let simulator = makeEndpointSimulator()
        simulator.recordTransportStatus(
            OutputEndpointStatus(endpointID: simulator.outputEndpoints[0].id, level: .idle, message: "idle")
        )
        #expect(simulator.transportHistory.isEmpty == false)

        simulator.clearTransportHistory()
        #expect(simulator.transportHistory.isEmpty)
    }
}

private func makeEndpointSimulator() -> NMEASimulator {
    let suiteName = "MarineSimulatorTests.Endpoints.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = true
    return simulator
}
