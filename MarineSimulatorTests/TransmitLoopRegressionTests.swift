import Foundation
import Testing
@testable import MarineSimulator

/// Locks the off-main 20 Hz loop after the `NMEASimulator+TransmitLoop` extract.
@Suite(.serialized)
struct TransmitLoopRegressionTests {

    @Test @MainActor
    func applyRuntimeToMainWritesGeneratedValueButKeepsUserSetpoint() {
        let simulator = makeLoopSimulator()
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 4, value: 90)

        var runtime = SimulationState(from: simulator)
        runtime.heading.value = 33
        runtime.heading.centerValue = 12
        runtime.heading.offset = 1

        simulator.applyRuntimeToMain(runtime, flushConsoleImmediately: true)

        #expect(simulator.heading.value == 33)
        #expect(simulator.heading.centerValue == 90)
        #expect(simulator.heading.offset == 4)
    }

    @Test @MainActor
    func applyRuntimeToMainPublishesSnapshotAndFlushesBufferedConsole() {
        let simulator = makeLoopSimulator()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        var runtime = SimulationState(from: simulator)
        runtime.latestSnapshot = SimulationSnapshot(
            timestamp: timestamp,
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 90,
            gyroHeading: 90,
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
        runtime.lastSimulationTickDate = timestamp

        simulator.transmitRuntime = runtime
        simulator.recordOutputMessage("$IIHDT,90.0,T*00\r\n", timestamp: timestamp)
        #expect(simulator.outputMessages.isEmpty)

        simulator.applyRuntimeToMain(runtime, flushConsoleImmediately: true)

        #expect(simulator.latestSnapshot?.timestamp == timestamp)
        #expect(simulator.outputMessages == ["$IIHDT,90.0,T*00\r\n"])
        #expect(simulator.outputMessageRecords.map(\.sentence) == simulator.outputMessages)
        #expect(simulator.consoleDisplayGeneration > 0)
        simulator.transmitRuntime = nil
    }

    @Test @MainActor
    func captureSimulationConfigReadsEnabledSentencesAndTalker() {
        let simulator = makeLoopSimulator()
        let config = simulator.captureSimulationConfig()

        #expect(config.talkerID == simulator.talkerID)
        #expect(config.sentenceToggles.shouldSendHDT)
        #expect(config.weatherSourceMode == .manual)
        #expect(config.enabledOutputEndpoints.isEmpty)
    }

    @Test @MainActor
    func runTransmitSimulationCycleBuffersHDTUntilFlush() {
        let simulator = makeLoopSimulator()
        simulator.syncInputMirror()
        simulator.transmitRuntime = SimulationState(from: simulator)
        defer { simulator.transmitRuntime = nil }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_200)
        simulator.runTransmitSimulationCycle(at: timestamp)

        #expect(simulator.outputMessages.isEmpty)
        #expect(simulator.allOutputMessageRecords.contains(where: { $0.sentence.contains("HDT") }))
        #expect(simulator.transmitRuntime?.latestSnapshot != nil)

        simulator.applyRuntimeToMain(simulator.transmitRuntime!, flushConsoleImmediately: true)
        #expect(simulator.outputMessages.contains(where: { $0.contains("HDT") }))
        #expect(simulator.latestSnapshot != nil)
    }

    @Test @MainActor
    func runTransmitSimulationCycleHonorsHDTInterval() {
        let simulator = makeLoopSimulator()
        simulator.syncInputMirror()
        simulator.transmitRuntime = SimulationState(from: simulator)
        defer { simulator.transmitRuntime = nil }

        let t0 = Date(timeIntervalSince1970: 1_700_000_300)
        simulator.runTransmitSimulationCycle(at: t0)
        simulator.runTransmitSimulationCycle(at: t0.addingTimeInterval(0.05))
        simulator.runTransmitSimulationCycle(at: t0.addingTimeInterval(0.10))

        let hdtCount = simulator.allOutputMessageRecords.filter { $0.sentence.contains("HDT") }.count
        #expect(hdtCount == 2)
    }

    @Test @MainActor
    func stopSimulationClearsRuntimeAndTimer() {
        let simulator = makeLoopSimulator()
        simulator.isTransmitting = true
        simulator.simulationQueue.sync {
            simulator.transmitRuntime = SimulationState(from: simulator)
            simulator.startSimulationTimer()
        }

        simulator.stopSimulation()

        #expect(simulator.isTransmitting == false)
        #expect(simulator.transmitRuntime == nil)
        #expect(simulator.simulationTimer == nil)
    }

    @Test @MainActor
    func timedLoopEmitsHDTAndStopHaltsFurtherMessages() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.weatherSourceMode = .manual
        simulator.outputEndpoints[0].isEnabled = false
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendHDT)
        simulator.clearOutputMessages()
        simulator.isTimerSelected = true
        defer { simulator.stopSimulation() }

        simulator.startSimulation()
        pumpMainRunLoop(for: 1.5)

        #expect(simulator.isTransmitting)
        let hdtCount = countSentences(in: simulator, matching: { $0.contains("HDT") }, duringLast: 1.2)
        #expect(hdtCount >= 6)
        #expect(hdtCount <= 16)
        simulator.simulationQueue.sync {
            #expect(simulator.transmitRuntime != nil)
            #expect(simulator.simulationTimer != nil)
        }

        simulator.stopSimulation()
        #expect(simulator.isTransmitting == false)
        #expect(simulator.transmitRuntime == nil)
        #expect(simulator.simulationTimer == nil)

        let countAfterStop = simulator.allOutputMessageRecords.count
        pumpMainRunLoop(for: 0.4)
        #expect(simulator.allOutputMessageRecords.count == countAfterStop)
    }

    @Test @MainActor
    func restartAfterStopTransmitsAgain() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.weatherSourceMode = .manual
        simulator.outputEndpoints[0].isEnabled = false
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendHDT)
        simulator.clearOutputMessages()
        simulator.isTimerSelected = true
        defer { simulator.stopSimulation() }

        simulator.startSimulation()
        pumpMainRunLoop(for: 0.8)
        simulator.stopSimulation()
        simulator.clearOutputMessages()

        simulator.startSimulation()
        pumpMainRunLoop(for: 1.2)

        #expect(simulator.isTransmitting)
        #expect(simulator.allOutputMessageRecords.contains(where: { $0.sentence.contains("HDT") }))
    }
}

@MainActor
private func makeLoopSimulator() -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: isolatedLoopDefaults())
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
    simulator.isTimerSelected = true
    simulator.clearOutputMessages()
    simulator.syncInputMirror()
    return simulator
}

private func configuredSimulatorForDeterministicOutput() -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: isolatedLoopDefaults())
    simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 10, offset: 0)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0)
    simulator.depth = SimulatedValue(type: .depth, center: 12, offset: 0)
    simulator.seaTemp = SimulatedValue(type: .seaTemp, center: 18, offset: 0)
    simulator.gpsData = GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90)
    simulator.mwvReferenceMode = .relative
    return simulator
}

private func onlyEnabledSentence(_ keyPath: WritableKeyPath<SentenceToggleStates, Bool>) -> SentenceToggleStates {
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
    toggles[keyPath: keyPath] = true
    return toggles
}

private func isolatedLoopDefaults() -> UserDefaults {
    let suiteName = "MarineSimulatorTests.TransmitLoop.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func countSentences(
    in simulator: NMEASimulator,
    matching predicate: (String) -> Bool,
    duringLast seconds: TimeInterval
) -> Int {
    let cutoff = Date().addingTimeInterval(-seconds)
    return simulator.allOutputMessageRecords.filter { record in
        predicate(record.sentence) && record.timestamp >= cutoff
    }.count
}

@MainActor
private func pumpMainRunLoop(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        Thread.sleep(forTimeInterval: 0.03)
    }
}
