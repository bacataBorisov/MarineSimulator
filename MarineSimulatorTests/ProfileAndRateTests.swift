import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct ProfileAndRateTests {

    @Test
    func eachHardwareProfileAppliesItsSentenceSetRatesAndSensors() {
        for profile in HardwareProfile.allCases where profile != .custom {
            let simulator = NMEASimulator(userDefaults: isolatedDefaults())
            let windCenter = simulator.twd.centerValue
            simulator.applyHardwareProfile(profile)

            #expect(simulator.selectedProfile == profile)
            #expect(simulator.sentenceRateMode == .realistic)
            #expect(simulator.twd.centerValue == windCenter)
            #expect(simulator.sensorToggles.hasAirTempSensor == false)
            #expect(simulator.sensorToggles.hasHumidtySensor == false)
            #expect(simulator.sensorToggles.hasBarometer == false)

            switch profile {
            case .bngTriton2:
                #expect(simulator.sensorToggles.hasGyro)
                #expect(simulator.sentenceToggles.shouldSendHDT)
                #expect(simulator.sentenceToggles.shouldSendGLL)
                #expect(simulator.sentenceIntervals[.hdg] == 0.1)
                #expect(simulator.sentenceIntervals[.vlw] == 5)
                #expect(simulator.interval == 0.1)
                #expect(simulator.talkerID(for: .hdg) == "HC")
                #expect(simulator.talkerID(for: .hdt) == "HE")
                #expect(simulator.talkerID(for: .rmc) == "GP")
            case .furunoFI70:
                #expect(simulator.sensorToggles.hasGyro == false)
                #expect(simulator.sensorToggles.hasCompass)
                #expect(simulator.sentenceToggles.shouldSendHDG)
                #expect(simulator.sentenceToggles.shouldSendHDT == false)
                #expect(simulator.sentenceToggles.shouldSendROT == false)
                #expect(simulator.sentenceIntervals[.hdg] == 1)
                #expect(simulator.interval == 1)
                #expect(simulator.talkerID(for: .hdg) == "HC")
            case .garminGMI20:
                #expect(simulator.sensorToggles.hasGyro)
                #expect(simulator.sentenceToggles.shouldSendGLL == false)
                #expect(simulator.sentenceToggles.shouldSendHDT)
                #expect(simulator.sentenceIntervals[.hdt] == 0.1)
                #expect(simulator.interval == 0.1)
                #expect(simulator.talkerID(for: .hdg) == "GP")
                #expect(simulator.talkerID(for: .mwv) == "GP")
            case .yachtDevicesGateway:
                #expect(simulator.sentenceIntervals[.hdg] == 0.1)
                #expect(simulator.sentenceIntervals[.rmc] == 0.2)
                #expect(simulator.sentenceIntervals[.gsa] == 5)
                #expect(simulator.interval == 0.1)
                #expect(simulator.talkerID(for: .hdt) == "HE")
            case .minimalGPS:
                #expect(simulator.sensorToggles.hasGPS)
                #expect(simulator.sensorToggles.hasAnemometer == false)
                #expect(simulator.sensorToggles.hasCompass == false)
                #expect(simulator.sensorToggles.hasGyro == false)
                #expect(simulator.sensorToggles.hasSpeedLog == false)
                #expect(simulator.sentenceToggles.shouldSendRMC)
                #expect(simulator.sentenceToggles.shouldSendGGA)
                #expect(simulator.sentenceToggles.shouldSendMWV == false)
                #expect(simulator.sentenceToggles.shouldSendGLL == false)
                #expect(simulator.sentenceIntervals[.rmc] == 1)
                #expect(simulator.sentenceIntervals[.gsa] == 5)
                #expect(simulator.interval == 1)
                #expect(simulator.talkerID(for: .rmc) == "GP")
            case .custom:
                break
            }
        }
    }

    @Test
    func customProfileKeepsTheCurrentConfiguration() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.applyHardwareProfile(.furunoFI70)
        simulator.sentenceToggles.shouldSendMWV = false

        simulator.applyHardwareProfile(.custom)

        #expect(simulator.selectedProfile == .custom)
        #expect(simulator.sentenceToggles.shouldSendHDT == false)
        #expect(simulator.sentenceToggles.shouldSendMWV == false)
        #expect(simulator.sentenceIntervals[.hdg] == 1)
        #expect(simulator.sensorToggles.hasGyro == false)
    }

    @Test
    func switchingProfilesRestoresThatProfileWithoutMovingSetpoints() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.twd.centerValue = 44
        simulator.heading.centerValue = 123

        simulator.applyHardwareProfile(.minimalGPS)
        #expect(simulator.twd.centerValue == 44)
        #expect(simulator.heading.centerValue == 123)
        #expect(simulator.sentenceToggles.shouldSendHDT == false)

        simulator.applyHardwareProfile(.bngTriton2)
        #expect(simulator.sentenceToggles.shouldSendHDT)
        #expect(simulator.sentenceIntervals[.hdg] == 0.1)
        #expect(simulator.twd.centerValue == 44)
        #expect(simulator.heading.centerValue == 123)
    }

    @Test
    func realisticModeRestoresTheSelectedProfileRatherThanBngIntervals() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.applyHardwareProfile(.furunoFI70)
        simulator.sentenceRateMode = .custom
        simulator.sentenceIntervals[.hdg] = 4

        simulator.sentenceRateMode = .realistic

        #expect(simulator.selectedProfile == .furunoFI70)
        #expect(simulator.sentenceIntervals[.hdg] == 1)
        #expect(simulator.sentenceToggles.shouldSendHDT == false)
        #expect(simulator.sensorToggles.hasGyro == false)
    }

    @Test
    func realisticModeFromCustomProfileAppliesBngTriton2() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.applyHardwareProfile(.furunoFI70)
        simulator.setInterval(3, for: .hdg)
        #expect(simulator.selectedProfile == .custom)
        #expect(simulator.sentenceRateMode == .custom)

        simulator.sentenceRateMode = .realistic

        #expect(simulator.selectedProfile == .bngTriton2)
        #expect(simulator.sentenceIntervals[.hdg] == 0.1)
        #expect(simulator.sentenceToggles.shouldSendHDT)
        #expect(simulator.sensorToggles.hasGyro)
    }

    @Test
    func customSentenceToggleAndRateAreHonoredOnAClock() {
        let simulator = makeRatedSimulator()
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.sentenceToggles.shouldSendMWV = false
        simulator.setInterval(0.5, for: .hdg)
        #expect(simulator.sentenceRateMode == .custom)

        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_100)
        let first = tick(state: &state, config: config, at: t0)
        #expect(first.contains(.hdg))
        #expect(first.contains(.mwv) == false)

        let early = tick(state: &state, config: config, at: t0.addingTimeInterval(0.4))
        #expect(early.contains(.hdg) == false)

        let due = tick(state: &state, config: config, at: t0.addingTimeInterval(0.5))
        #expect(due.contains(.hdg))
    }

    @Test
    func zeroSentenceIntervalEmitsEveryFastTickAndNegativeIntervalsClampToZero() {
        let simulator = makeRatedSimulator()
        simulator.setInterval(-2, for: .rmc)
        #expect(simulator.sentenceIntervals[.rmc] == 0)

        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_200)
        #expect(tick(state: &state, config: config, at: t0).contains(.rmc))
        #expect(tick(state: &state, config: config, at: t0.addingTimeInterval(0.05)).contains(.rmc))
    }

    @Test
    func environmentEvolutionIsOneHertzWhilePhysicsAndNmeaStayFaster() {
        let simulator = makeRatedSimulator()
        simulator.interval = 0.1
        simulator.sentenceIntervals[.hdt] = 0.1
        simulator.sentenceToggles = onlyEnabled(\.shouldSendHDT)
        simulator.sensorToggles.hasGyro = true
        simulator.sensorToggles.hasCompass = true
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
        simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)

        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_300)
        let startLongitude = state.gpsData.longitude
        var hdtCount = 0

        for step in 0...10 {
            let due = tick(state: &state, config: config, at: t0.addingTimeInterval(Double(step) * 0.05))
            if due.contains(.hdt) {
                hdtCount += 1
            }
        }

        #expect(hdtCount >= 5)
        #expect(hdtCount <= 6)
        #expect(state.lastSensorEvolutionDate == t0)
        #expect(state.tws.value == 12)
        #expect(state.environmentTruth.trueWindSpeedKnots == 12)
        #expect(state.gpsData.longitude > startLongitude)
        #expect(NMEASimulator.simulationFastTickInterval == 0.05)
        #expect(NMEASimulator.displayPublishInterval == 0.1)
        #expect(SimulationEngine.environmentEvolutionInterval == 1)
    }

    @Test
    func offsetZeroStaysOnCenterAndACenterChangeAppliesOnTheNextEvolution() {
        let simulator = makeRatedSimulator()
        simulator.tws = SimulatedValue(type: .windSpeed, center: 10, offset: 2, value: 10)
        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let t0 = Date(timeIntervalSince1970: 1_800_000_400)

        _ = tick(state: &state, config: config, at: t0)
        let evolved = state.tws.value ?? -1
        #expect((8...12).contains(evolved))

        state.tws.centerValue = 20
        _ = tick(state: &state, config: config, at: t0.addingTimeInterval(0.05))
        #expect(state.tws.value == evolved)
        #expect(state.environmentTruth.trueWindSpeedKnots == evolved)

        _ = tick(state: &state, config: config, at: t0.addingTimeInterval(1))
        let redrawn = state.tws.value ?? -1
        #expect((18...22).contains(redrawn))
        #expect(state.environmentTruth.trueWindSpeedKnots == redrawn)
    }

    @Test
    func manualAndFromWindBothWorkUnderCustomRates() {
        let manual = makeRatedSimulator()
        manual.sentenceRateMode = .custom
        manual.boatSpeedMode = .manual
        manual.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
        var manualState = SimulationState(from: manual)
        _ = tick(state: &manualState, config: manual.captureSimulationConfig(), at: Date(timeIntervalSince1970: 1_800_000_500))
        #expect(manualState.vesselTruth.speedThroughWaterKnots == 6)
        #expect(manualState.latestSnapshot?.boatSpeed == 6)

        let estimated = makeRatedSimulator()
        estimated.sentenceRateMode = .custom
        estimated.boatSpeedMode = .estimated
        estimated.sensorToggles.hasGyro = false
        estimated.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        estimated.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
        estimated.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
        estimated.speed.offset = 0
        var estimatedState = SimulationState(from: estimated)
        _ = tick(
            state: &estimatedState,
            config: estimated.captureSimulationConfig(),
            at: Date(timeIntervalSince1970: 1_800_000_600)
        )
        #expect((estimatedState.vesselTruth.speedThroughWaterKnots ?? 0) > 3)
        #expect(estimatedState.latestSnapshot?.boatSpeed == estimatedState.speed.value)
        #expect(estimatedState.environmentTruth.trueWindSpeedKnots == 12)
    }

    @Test
    func profileChangeHidesDisabledSensorsWithoutErasingTruth() {
        let simulator = makeRatedSimulator()
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
        simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
        var state = SimulationState(from: simulator)
        let t0 = Date(timeIntervalSince1970: 1_800_000_700)
        _ = tick(state: &state, config: simulator.captureSimulationConfig(), at: t0)
        let wind = state.environmentTruth.trueWindSpeedKnots
        let heading = state.vesselTruth.magneticHeading

        simulator.applyHardwareProfile(.minimalGPS)
        _ = tick(
            state: &state,
            config: simulator.captureSimulationConfig(),
            at: t0.addingTimeInterval(0.05)
        )

        #expect(state.environmentTruth.trueWindSpeedKnots == wind)
        #expect(state.vesselTruth.magneticHeading == heading)
        #expect(state.tws.value == nil)
        #expect(state.heading.value == nil)
        #expect(state.latestSnapshot?.windSpeedTrue == nil)
        #expect(state.latestSnapshot?.magneticHeading == nil)
        let active = SimulationEngine.activeSentenceTypes(
            snapshot: state.latestSnapshot!,
            config: simulator.captureSimulationConfig()
        )
        #expect(active.contains(.mwv) == false)
        #expect(active.contains(.hdg) == false)
        #expect(active.contains(.rmc))
    }

    @Test
    func rmcAndVtgShareTheSameSnapshotSpeed() {
        let simulator = makeRatedSimulator()
        simulator.speed = SimulatedValue(type: .speedLog, center: 6.3, offset: 0, value: 6.3)
        simulator.gpsData.speedOverGround = 6.3
        var state = SimulationState(from: simulator)
        let snapshot = SimulationEngine.tickSimulation(
            state: &state,
            config: simulator.captureSimulationConfig(),
            at: Date(timeIntervalSince1970: 1_800_000_800),
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        let sog = NMEANumericFormatting.format(snapshot.gpsData.speedOverGround, fractionDigits: 1)
        let rmc = simulator.buildNMEASentences(talkerID: "GP", type: .rmc, snapshot: snapshot)[0]
        let vtg = simulator.buildNMEASentences(talkerID: "GP", type: .vtg, snapshot: snapshot)[0]
        #expect(rmc.contains(",\(sog),"))
        #expect(vtg.contains(",\(sog),N,"))
    }

    @Test
    func gnssAndDscTogglesDoNotChangeTheSentenceSet() {
        let simulator = makeRatedSimulator()
        simulator.applyHardwareProfile(.bngTriton2)
        var state = SimulationState(from: simulator)
        let config = simulator.captureSimulationConfig()
        let snapshot = SimulationEngine.tickSimulation(
            state: &state,
            config: config,
            at: Date(timeIntervalSince1970: 1_800_000_900),
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        let before = SimulationEngine.activeSentenceTypes(snapshot: snapshot, config: config)
        simulator.sensorToggles.shouldSendGNSS = true
        simulator.sensorToggles.shouldSendDSC = true
        let after = SimulationEngine.activeSentenceTypes(
            snapshot: snapshot,
            config: simulator.captureSimulationConfig()
        )
        #expect(before == after)
    }

    @Test
    func runtimeIntervalChangeIsUsedByTheNextTransmitCycle() {
        let simulator = makeRatedSimulator()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles = onlyEnabled(\.shouldSendHDG)
        simulator.syncInputMirror()
        simulator.transmitRuntime = SimulationState(from: simulator)
        defer { simulator.transmitRuntime = nil }

        let t0 = Date(timeIntervalSince1970: 1_800_001_000)
        simulator.runTransmitSimulationCycle(at: t0)
        simulator.setInterval(2, for: .hdg)
        simulator.runTransmitSimulationCycle(at: t0.addingTimeInterval(0.5))

        let runtime = simulator.transmitRuntime!
        #expect(runtime.lastEmissionDates[.hdg] == t0)
        #expect(simulator.sentenceRateMode == .custom)
    }
}

private func makeRatedSimulator() -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: isolatedDefaults())
    simulator.weatherSourceMode = .manual
    simulator.boatSpeedMode = .manual
    simulator.interval = 1
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    simulator.depth = SimulatedValue(type: .depth, center: 12, offset: 0, value: 12)
    simulator.seaTemp = SimulatedValue(type: .seaTemp, center: 18, offset: 0, value: 18)
    simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
    return simulator
}

private func tick(
    state: inout SimulationState,
    config: SimulationConfig,
    at timestamp: Date
) -> [NMEASentenceType] {
    let snapshot = SimulationEngine.tickSimulation(
        state: &state,
        config: config,
        at: timestamp,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
    return SimulationEngine.scheduledSentenceTypes(
        state: &state,
        at: timestamp,
        snapshot: snapshot,
        config: config
    )
}

private func onlyEnabled(_ keyPath: WritableKeyPath<SentenceToggleStates, Bool>) -> SentenceToggleStates {
    var toggles = SentenceToggleStates(
        shouldSendMWV: false, shouldSendMWD: false, shouldSendVPW: false,
        shouldSendHDG: false, shouldSendHDT: false, shouldSendROT: false,
        shouldSendRMC: false, shouldSendGGA: false, shouldSendVTG: false,
        shouldSendGLL: false, shouldSendGSA: false, shouldSendGSV: false,
        shouldSendZDA: false, shouldSendDBT: false, shouldSendDPT: false,
        shouldSendVHW: false, shouldSendVLW: false, shouldSendVBW: false,
        shouldSendMTW: false, shouldSendRMB: false, shouldSendXTE: false
    )
    toggles[keyPath: keyPath] = true
    return toggles
}

private func isolatedDefaults() -> UserDefaults {
    let name = "ProfileAndRateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
