import Foundation
import Testing
@testable import MarineSimulator

/// Locks idle vs transmit cycle writeback after the shared wrapper extract.
@Suite(.serialized)
struct CycleUnificationTests {

    @Test @MainActor
    func idleCycleWritesOutputMessagesImmediately() {
        let simulator = makeCycleSimulator()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_400)

        simulator.runSimulationCycle(at: timestamp)

        #expect(simulator.transmitRuntime == nil)
        #expect(simulator.outputMessages.contains(where: { $0.contains("HDT") }))
        #expect(simulator.outputMessageRecords.contains(where: { $0.sentence.contains("HDT") }))
        #expect(simulator.latestSnapshot != nil)
    }

    @Test @MainActor
    func startSimulationWithoutTimerStillFillsOutputMessagesAndStops() {
        let simulator = makeCycleSimulator()
        simulator.isTimerSelected = false

        simulator.startSimulation()

        #expect(simulator.isTransmitting == false)
        #expect(simulator.transmitRuntime == nil)
        #expect(simulator.outputMessages.isEmpty == false)
        #expect(simulator.outputMessages.contains(where: { $0.contains("HDT") }))
        #expect(simulator.transportHistory.contains { $0.category == .lifecycle && $0.message == "Single transmission sent" })
    }

    @Test @MainActor
    func idleAndTransmitCyclesEmitTheSameHDTSentence() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_410)

        let idle = makeCycleSimulator()
        idle.runSimulationCycle(at: timestamp)
        let idleHDT = sentences(in: idle, matching: { $0.contains("HDT") })

        let transmit = makeCycleSimulator()
        transmit.transmitRuntime = SimulationState(from: transmit)
        defer { transmit.transmitRuntime = nil }
        transmit.runTransmitSimulationCycle(at: timestamp)
        let transmitHDT = sentences(in: transmit, matching: { $0.contains("HDT") })

        #expect(idleHDT.count == 1)
        #expect(transmitHDT == idleHDT)
        #expect(idle.outputMessages.contains(where: { $0.contains("HDT") }))
        #expect(transmit.outputMessages.isEmpty)
    }

    @Test @MainActor
    func idleCycleHonorsHDTInterval() {
        let simulator = makeCycleSimulator()
        let t0 = Date(timeIntervalSince1970: 1_700_000_420)

        simulator.runSimulationCycle(at: t0)
        simulator.runSimulationCycle(at: t0.addingTimeInterval(0.05))
        simulator.runSimulationCycle(at: t0.addingTimeInterval(0.10))

        let hdtCount = simulator.outputMessages.filter { $0.contains("HDT") }.count
        #expect(hdtCount == 2)
    }

    @Test @MainActor
    func transmitCycleKeepsUserSetpointAfterSharedWrapper() {
        let simulator = makeCycleSimulator()
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 4, value: 90)
        simulator.syncInputMirror()
        simulator.transmitRuntime = SimulationState(from: simulator)
        defer { simulator.transmitRuntime = nil }

        simulator.runTransmitSimulationCycle(at: Date(timeIntervalSince1970: 1_700_000_430))
        simulator.applyRuntimeToMain(simulator.transmitRuntime!, flushConsoleImmediately: true)

        #expect(simulator.heading.centerValue == 90)
        #expect(simulator.heading.offset == 4)
        #expect(simulator.heading.value != nil)
    }

    @Test @MainActor
    func nextMWVReferenceSelfMatchesInout() {
        let simulator = makeCycleSimulator()
        simulator.mwvReferenceMode = .auto
        simulator.sendRelativeWind = true
        let snapshot = SimulationSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_440),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 0,
            gyroHeading: 0,
            magneticVariation: 0,
            compassDeviation: 0,
            boatSpeed: 6,
            depth: 12,
            seaTemperature: 18,
            airTemperature: 22,
            relativeHumidity: 65,
            airPressure: 1013,
            gpsData: simulator.gpsData,
            gpsSignal: GPSSignalSnapshot(
                fixQuality: 1,
                fixMode: 3,
                selectionMode: "A",
                satellitesUsed: 8,
                hdop: 0.9,
                vdop: 1.1,
                pdop: 1.4,
                altitudeMeters: 14,
                geoidalSeparationMeters: 36,
                satellites: []
            ),
            turnRate: 0,
            logDistanceNm: 1,
            tripDistanceNm: 0.2,
            navigationTarget: nil
        )

        var toggle = true
        let fromSelf = simulator.nextMWVReference(in: snapshot)
        let fromInout = simulator.nextMWVReference(
            in: snapshot,
            sendRelativeWind: &toggle,
            mwvReferenceMode: .auto
        )

        #expect(fromSelf == "R")
        #expect(fromInout == "R")
        #expect(simulator.sendRelativeWind == false)
        #expect(toggle == false)

        let secondSelf = simulator.nextMWVReference(in: snapshot)
        let secondInout = simulator.nextMWVReference(
            in: snapshot,
            sendRelativeWind: &toggle,
            mwvReferenceMode: .auto
        )
        #expect(secondSelf == "T")
        #expect(secondInout == "T")
        #expect(simulator.sendRelativeWind == true)
        #expect(toggle == true)
    }
}

@MainActor
private func makeCycleSimulator() -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: isolatedCycleDefaults())
    simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 10, offset: 0)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0)
    simulator.depth = SimulatedValue(type: .depth, center: 12, offset: 0)
    simulator.seaTemp = SimulatedValue(type: .seaTemp, center: 18, offset: 0)
    simulator.gpsData = GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90)
    simulator.mwvReferenceMode = .relative
    simulator.weatherSourceMode = .manual
    simulator.outputEndpoints[0].isEnabled = false
    simulator.applyHardwareProfile(.bngTriton2)
    var toggles = SentenceToggleStates(
        shouldSendMWV: false,
        shouldSendMWD: false,
        shouldSendVPW: false,
        shouldSendHDG: false,
        shouldSendHDT: false,
        shouldSendROT: false,
        shouldSendRMC: false,
        shouldSendGGA: false,
        shouldSendVTG: false,
        shouldSendGLL: false,
        shouldSendGSA: false,
        shouldSendGSV: false,
        shouldSendZDA: false,
        shouldSendDBT: false,
        shouldSendDPT: false,
        shouldSendVHW: false,
        shouldSendVLW: false,
        shouldSendVBW: false,
        shouldSendMTW: false,
        shouldSendRMB: false,
        shouldSendXTE: false
    )
    toggles.shouldSendHDT = true
    simulator.sentenceToggles = toggles
    simulator.isTimerSelected = false
    simulator.clearOutputMessages()
    simulator.syncInputMirror()
    return simulator
}

private func sentences(in simulator: NMEASimulator, matching predicate: (String) -> Bool) -> [String] {
    simulator.allOutputMessageRecords.map(\.sentence).filter(predicate)
}

private func isolatedCycleDefaults() -> UserDefaults {
    let suiteName = "MarineSimulatorTests.CycleUnification.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
