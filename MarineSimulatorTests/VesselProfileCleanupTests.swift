import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselProfileCleanupTests {

    @Test
    func onlyExtasyAndNimanaRemainSelectable() {
        #expect(BoatProfile.allCases == [.beneteauFirst407, .nimana])
        #expect(BoatProfile.beneteauFirst407.displayName.contains("Extasy"))
        #expect(BoatProfile.beneteauFirst407.displayName.contains("1999"))
        #expect(BoatProfile.nimana.displayName.contains("Nimana"))
        #expect(BoatProfile.nimana.displayName.contains("2015"))
        #expect(BoatProfile.nimana.summary.contains("pending"))
        #expect(BoatProfile.nimana.hasSpeedPolar == false)
        #expect(BoatProfile.beneteauFirst407.hasSpeedPolar == true)
    }

    @Test
    func unknownSelectionStaysUnresolvedWithoutTouchingOtherSettings() throws {
        let suite = "VesselCleanup.unknown.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let seed = NMEASimulator(userDefaults: defaults)
        seed.port = 4957
        seed.talkerID = "XY"
        seed.boatSpeedMode = .estimated
        seed.boatProfile = .nimana
        seed.persistLiveSettings()

        let key = "marine_simulator.settings"
        let data = try #require(defaults.data(forKey: key))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["activeVesselID"] = "not-a-vessel"
        object["vesselSelectionWasStored"] = true
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)

        let restored = NMEASimulator(userDefaults: defaults)
        #expect(restored.selectedVesselID == nil)
        if case .unresolved(let reference) = restored.activeVesselState {
            #expect(reference == "not-a-vessel")
        } else {
            Issue.record("Expected an unresolved vessel")
        }
        #expect(restored.port == 4957)
        #expect(restored.talkerID == "XY")
        #expect(restored.boatSpeedMode == .estimated)
        #expect(restored.isTransmitting == false)
        restored.startSimulation()
        #expect(restored.isTransmitting == false)
        restored.persistLiveSettings()

        let again = NMEASimulator(userDefaults: defaults)
        #expect(again.selectedVesselID == nil)
        let storedData = try #require(defaults.data(forKey: key))
        let stored = try #require(JSONSerialization.jsonObject(with: storedData) as? [String: Any])
        #expect(stored["activeVesselID"] as? String == "not-a-vessel")
        #expect(stored["talkerID"] as? String == "XY")
        #expect(stored["port"] as? Int == 4957)
    }

    @Test
    func nimanaSelectionSurvivesRestart() throws {
        let suite = "VesselCleanup.nimana.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let seed = NMEASimulator(userDefaults: defaults)
        seed.boatProfile = .nimana
        seed.port = 4960
        seed.persistLiveSettings()

        let restored = NMEASimulator(userDefaults: defaults)
        #expect(restored.boatProfile == .nimana)
        #expect(restored.port == 4960)
    }

    @Test
    func extasyFromWindUsesTheFarrPolarAndNimanaHoldsSpeed() {
        let extasy = tick(profile: .beneteauFirst407, mode: .estimated, speed: 4)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs(polar - 8.18) < 0.01)
        #expect(abs((extasy.speed ?? 0) - polar) < 0.000_001)

        let nimana = tick(profile: .nimana, mode: .estimated, speed: 6.5)
        #expect(BoatProfile.nimana.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) == nil)
        #expect(abs((nimana.speed ?? 0) - 6.5) < 0.000_001)

        let manual = tick(profile: .beneteauFirst407, mode: .manual, speed: 4)
        #expect(abs((manual.speed ?? 0) - 4) < 0.000_001)
        #expect(abs((manual.gyro ?? 0) - (manual.trueHeading ?? -1)) < 0.000_001)
    }

    @Test
    func nimanaStillEmitsHeadingSentences() {
        let sample = tick(profile: .nimana, mode: .manual, speed: 6)
        let sentences = sample.simulator.buildNMEASentences(talkerID: "II", type: .hdt, snapshot: sample.snapshot)
        #expect(sentences.count == 1)
        #expect(sentences[0].contains("HDT"))
        #expect(sample.gyro != nil)
    }

    @Test @MainActor
    func tackAndGybeStillStartOnBothVessels() {
        for profile in BoatProfile.allCases {
            let simulator = makeCleanupSimulator()
            simulator.boatProfile = profile
            simulator.beginManeuver(.tack(.port))
            #expect(simulator.isTackInProgress)
            simulator.cancelManeuver()
            #expect(!simulator.isTackInProgress)
            simulator.beginManeuver(.gybe(.port))
            #expect(simulator.isTackInProgress)
            simulator.cancelManeuver()
        }
    }
}

private struct CleanupSample {
    let simulator: NMEASimulator
    let snapshot: SimulationSnapshot
    let speed: Double?
    let gyro: Double?
    let trueHeading: Double?
}

private func tick(profile: BoatProfile, mode: BoatSpeedMode, speed: Double) -> CleanupSample {
    let simulator = makeCleanupSimulator()
    simulator.boatProfile = profile
    simulator.boatSpeedMode = mode
    simulator.speed = SimulatedValue(type: .speedLog, center: speed, offset: 0, value: speed)
    var state = SimulationState(from: simulator)
    let time = Date(timeIntervalSince1970: 1_800_005_000)
    state.lastSensorEvolutionDate = time
    state.lastSimulationTickDate = time.addingTimeInterval(-0.05)
    let snapshot = SimulationEngine.tickSimulation(
        state: &state,
        config: simulator.captureSimulationConfig(),
        at: time,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
    return CleanupSample(
        simulator: simulator,
        snapshot: snapshot,
        speed: state.vesselTruth.speedThroughWaterKnots,
        gyro: state.gyroHeading.value,
        trueHeading: state.vesselTruth.trueHeading
    )
}

private func makeCleanupSimulator() -> NMEASimulator {
    let suite = "VesselCleanup.sim.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasGPS = true
    simulator.sensorToggles.hasSpeedLog = true
    let time = Date(timeIntervalSince1970: 1_800_005_000)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    return simulator
}
