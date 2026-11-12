import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct TruthSeparationTests {

    @Test
    func sensorEditsDoNotChangeEnvironmentOrVesselTruth() {
        let simulator = makeTruthSimulator()
        simulator.boatSpeedMode = .manual
        simulator.interval = 1
        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        _ = SimulationEngine.tickSimulation(
            state: &state,
            config: config,
            at: t0,
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        let environment = state.environmentTruth
        let vessel = state.vesselTruth

        state.tws.value = 1
        state.twd.value = 10
        state.heading.value = 0
        state.speed.value = 20
        state.gpsData.latitude += 1

        #expect(state.environmentTruth == environment)
        #expect(state.vesselTruth == vessel)

        _ = SimulationEngine.tickSimulation(
            state: &state,
            config: config,
            at: t0.addingTimeInterval(0.05),
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )

        #expect(state.environmentTruth.trueWindSpeedKnots == environment.trueWindSpeedKnots)
        #expect(state.vesselTruth.magneticHeading == vessel.magneticHeading)
        #expect(state.speed.value == vessel.speedThroughWaterKnots)
        #expect(abs(state.gpsData.latitude - vessel.latitude) < 0.01)
    }

    @Test
    func manualModeKeepsCommandedSpeedAndMovesEast() {
        let simulator = makeTruthSimulator()
        simulator.boatSpeedMode = .manual
        simulator.interval = 1
        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_100)

        _ = SimulationEngine.tickSimulation(
            state: &state, config: config, at: t0,
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        let startLon = state.vesselTruth.longitude
        _ = SimulationEngine.tickSimulation(
            state: &state, config: config, at: t0.addingTimeInterval(1),
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )

        #expect(state.speed.value == 6)
        #expect(state.vesselTruth.speedThroughWaterKnots == 6)
        #expect(state.vesselTruth.longitude > startLon)
        #expect(state.latestSnapshot?.boatSpeed == state.speed.value)
        #expect(state.latestSnapshot?.gpsData.latitude == state.gpsData.latitude)
        #expect(state.latestSnapshot?.gpsData.longitude == state.gpsData.longitude)
    }

    @Test
    func fromWindModeUsesPolarAndIgnoresSensorWindPoke() {
        let simulator = makeTruthSimulator()
        simulator.boatSpeedMode = .estimated
        simulator.interval = 1
        simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_200)

        _ = SimulationEngine.tickSimulation(
            state: &state, config: config, at: t0,
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        let polarSpeed = state.vesselTruth.speedThroughWaterKnots ?? 0
        #expect(polarSpeed > 3)

        state.tws.value = 1
        _ = SimulationEngine.tickSimulation(
            state: &state, config: config, at: t0.addingTimeInterval(0.05),
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )

        #expect(state.environmentTruth.trueWindSpeedKnots == 12)
        #expect(abs((state.vesselTruth.speedThroughWaterKnots ?? 0) - polarSpeed) < 0.05)
        #expect(state.latestSnapshot?.windSpeedTrue == 12)
        #expect(abs((state.latestSnapshot?.boatSpeed ?? 0) - polarSpeed) < 0.05)
    }

    @Test
    func seededManualEvolutionIsReproducible() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_300)
        var first = seededState(seed: 41)
        var second = seededState(seed: 41)
        var different = seededState(seed: 42)
        let config = seededConfig()

        for offset in [0, 1, 2] {
            let timestamp = t0.addingTimeInterval(TimeInterval(offset))
            _ = SimulationEngine.tickSimulation(
                state: &first, config: config, at: timestamp,
                liveWeatherValueGenerator: { base, _, _, _ in base }
            )
            _ = SimulationEngine.tickSimulation(
                state: &second, config: config, at: timestamp,
                liveWeatherValueGenerator: { base, _, _, _ in base }
            )
            _ = SimulationEngine.tickSimulation(
                state: &different, config: config, at: timestamp,
                liveWeatherValueGenerator: { base, _, _, _ in base }
            )
        }

        #expect(first.environmentTruth == second.environmentTruth)
        #expect(first.vesselTruth == second.vesselTruth)
        #expect(first.depth.value == second.depth.value)
        #expect(first.gpsData.latitude == second.gpsData.latitude)
        #expect(first.tws.value != different.tws.value)
    }

    @Test
    func experimentScenarioKeepsTruthSeparateAndSanitizesInputs() throws {
        let scenario = ExperimentScenario(
            name: "  ",
            seed: 99,
            referencePolarProfile: .beneteauFirst407,
            hiddenPolarProfile: .nimana,
            windProgram: .steady(trueWindDirectionDegrees: -10, speedKnots: -2),
            currentProgram: .init(setDegrees: 725, driftKnots: -1),
            outputContract: .init(
                measurementFields: [.timestamp, .speedThroughWater, .timestamp],
                permitsGroundTruthExport: false
            ),
            durationSeconds: .infinity,
            sampleIntervalSeconds: 0
        ).sanitized()

        #expect(scenario.formatVersion == ExperimentScenario.supportedFormatVersion)
        #expect(scenario.name == "Untitled experiment")
        #expect(scenario.referencePolarProfile == .beneteauFirst407)
        #expect(scenario.hiddenPolarProfile == .nimana)
        #expect(scenario.windProgram.trueWindDirectionDegrees == 350)
        #expect(scenario.windProgram.speedKnots == 0)
        #expect(scenario.currentProgram.setDegrees == 5)
        #expect(scenario.currentProgram.driftKnots == 0)
        #expect(scenario.outputContract.measurementFields == [.timestamp, .speedThroughWater])
        #expect(!scenario.outputContract.permitsGroundTruthExport)
        #expect(scenario.durationSeconds == 1_800)
        #expect(scenario.sampleIntervalSeconds == 0.05)

        let decoded = try JSONDecoder().decode(
            ExperimentScenario.self,
            from: JSONEncoder().encode(scenario)
        )
        #expect(decoded == scenario)
    }
}

private func makeTruthSimulator() -> NMEASimulator {
    let suite = "TruthSeparation.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.sensorToggles.hasGyro = false
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasGPS = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0, value: 90)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 10, offset: 0, value: 10)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
    return simulator
}

private func seededState(seed: UInt64) -> SimulationState {
    let simulator = makeTruthSimulator()
    simulator.twd.offset = 12
    simulator.tws.offset = 4
    simulator.heading.offset = 15
    simulator.depth.offset = 12
    simulator.speed.offset = 3
    var state = SimulationState(from: simulator)
    state.enableExperimentRandomness(seed: seed)
    return state
}

private func seededConfig() -> SimulationConfig {
    let simulator = makeTruthSimulator()
    simulator.twd.offset = 12
    simulator.tws.offset = 4
    simulator.heading.offset = 15
    simulator.depth.offset = 12
    simulator.speed.offset = 3
    return simulator.captureSimulationConfig()
}
