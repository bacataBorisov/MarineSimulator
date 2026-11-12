import Foundation
import Testing
@testable import MarineSimulator

/// Locks the current boundary between physical variation and published readings.
/// These tests describe today's behavior. They do not add a measurement-error layer.
@Suite(.serialized)
struct MeasurementBoundaryTests {

    @Test
    func environmentalWindRedrawReplacesTruthAndChangesEstimatedSpeed() {
        let start = Date(timeIntervalSince1970: 1_800_020_000)
        var redrawn = boundaryState(seed: 7, windSpeedOffset: 4)
        var steady = boundaryState(seed: 7, windSpeedOffset: 0)
        let redrawnConfig = boundaryConfig(windSpeedOffset: 4, boatSpeedMode: .estimated)
        let steadyConfig = boundaryConfig(windSpeedOffset: 0, boatSpeedMode: .estimated)

        tick(&redrawn, redrawnConfig, at: start)
        tick(&steady, steadyConfig, at: start)

        let expectedWind = expectedSample(seed: 7, draw: 1, center: 12, offset: 4, range: SimulatedValueType.windSpeed.defaultRange)
        #expect(expectedWind != 12)
        #expect(redrawn.environmentTruth.trueWindSpeedKnots == expectedWind)
        #expect(redrawn.tws.value == expectedWind)
        #expect(redrawn.latestSnapshot?.windSpeedTrue == expectedWind)
        #expect(steady.environmentTruth.trueWindSpeedKnots == 12)
        #expect(steady.vesselTruth.speedThroughWaterKnots != redrawn.vesselTruth.speedThroughWaterKnots)

        let evolvedSpeed = redrawn.vesselTruth.speedThroughWaterKnots ?? -1
        let evolvedAngle = abs(calculateShortestRotation(
            from: redrawn.vesselTruth.trueHeading,
            to: redrawn.environmentTruth.trueWindDirection ?? 0
        ))
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(
            trueWindSpeedKnots: expectedWind,
            trueWindAngleDegrees: evolvedAngle
        ) ?? -2
        #expect(abs(evolvedSpeed - polar) < 0.000_001)

        var relative = false
        let sentence = boundarySimulator().buildNMEASentences(
            talkerID: "II",
            type: .mwv,
            snapshot: redrawn.latestSnapshot!,
            sendRelativeWind: &relative,
            config: redrawnConfig
        ).first ?? ""
        #expect(sentence.contains(NMEANumericFormatting.format(expectedWind, fractionDigits: 1)))
        #expect(sentence.contains(",12.0,") == false)
    }

    @Test
    func environmentalHeadingRedrawChangesTheTrack() {
        let start = Date(timeIntervalSince1970: 1_800_020_100)
        var steady = boundaryState(seed: 4, headingOffset: 0)
        var redrawn = boundaryState(seed: 4, headingOffset: 20)
        let steadyConfig = boundaryConfig(headingOffset: 0, boatSpeedMode: .manual)
        let redrawnConfig = boundaryConfig(headingOffset: 20, boatSpeedMode: .manual)

        tick(&steady, steadyConfig, at: start)
        tick(&redrawn, redrawnConfig, at: start)
        #expect(redrawn.vesselTruth.magneticHeading != steady.vesselTruth.magneticHeading)
        #expect(redrawn.heading.value == redrawn.vesselTruth.magneticHeading)

        tick(&steady, steadyConfig, at: start.addingTimeInterval(0.05))
        tick(&redrawn, redrawnConfig, at: start.addingTimeInterval(0.05))
        #expect(redrawn.vesselTruth.trueHeading != steady.vesselTruth.trueHeading)
        #expect(redrawn.vesselTruth.longitude != steady.vesselTruth.longitude)
        #expect(redrawn.latestSnapshot?.magneticHeading == redrawn.heading.value)
    }

    @Test
    func speedOffsetScalesEstimatedSpeedAsAPhysicalModifier() {
        let start = Date(timeIntervalSince1970: 1_800_020_200)
        var plain = boundaryState(seed: 3, speedOffset: 0)
        var penalized = boundaryState(seed: 3, speedOffset: 10)
        let plainConfig = boundaryConfig(boatSpeedMode: .estimated, speedOffset: 0)
        let penalizedConfig = boundaryConfig(boatSpeedMode: .estimated, speedOffset: 10)

        tick(&plain, plainConfig, at: start)
        tick(&penalized, penalizedConfig, at: start)

        let plainSpeed = plain.vesselTruth.speedThroughWaterKnots ?? -1
        let penalizedSpeed = penalized.vesselTruth.speedThroughWaterKnots ?? -1
        #expect(abs(penalizedSpeed - plainSpeed * 0.9) < 0.000_001)
        #expect(plain.environmentTruth == penalized.environmentTruth)
    }

    @Test
    func wireFaultsDoNotChangePhysicalTruth() {
        let start = Date(timeIntervalSince1970: 1_800_020_300)
        var clean = boundaryState(seed: 5)
        var faulty = clean
        let cleanConfig = boundaryConfig(boatSpeedMode: .estimated)
        var faultSettings = FaultInjectionSettings()
        faultSettings.isEnabled = true
        faultSettings.dropRate = 1
        let faultyConfig = replacing(cleanConfig, faults: faultSettings)

        tick(&clean, cleanConfig, at: start)
        tick(&faulty, faultyConfig, at: start)
        #expect(clean.environmentTruth == faulty.environmentTruth)
        #expect(clean.vesselTruth == faulty.vesselTruth)

        let snapshot = clean.latestSnapshot!
        var relative = false
        let built = boundarySimulator().buildNMEASentences(
            talkerID: "II",
            type: .mwv,
            snapshot: snapshot,
            sendRelativeWind: &relative,
            config: cleanConfig
        )
        let dropped = SentenceScheduler.applyFaultInjection(
            to: built,
            for: .mwv,
            at: start,
            faultInjection: faultSettings,
            interval: 1
        )
        #expect(built.isEmpty == false)
        #expect(dropped.transmitted.isEmpty)
        #expect(clean.environmentTruth == faulty.environmentTruth)
        #expect(clean.vesselTruth == faulty.vesselTruth)
    }

    @Test
    func disablingDepthBlanksItsSentenceAndLeavesVesselTruth() {
        let start = Date(timeIntervalSince1970: 1_800_020_400)
        var state = boundaryState(seed: 6)
        let enabled = boundaryConfig(boatSpeedMode: .manual)
        tick(&state, enabled, at: start)
        #expect(state.latestSnapshot?.depth != nil)
        var withDepth = state
        var withoutDepth = state
        let disabled = replacing(enabled, echoSounder: false)
        let next = start.addingTimeInterval(0.05)
        tick(&withDepth, enabled, at: next)
        tick(&withoutDepth, disabled, at: next)

        #expect(withoutDepth.vesselTruth.latitude == withDepth.vesselTruth.latitude)
        #expect(withoutDepth.vesselTruth.longitude == withDepth.vesselTruth.longitude)
        #expect(withoutDepth.vesselTruth.trueHeading == withDepth.vesselTruth.trueHeading)
        #expect(withoutDepth.vesselTruth.speedThroughWaterKnots == withDepth.vesselTruth.speedThroughWaterKnots)
        #expect(withoutDepth.environmentTruth == withDepth.environmentTruth)
        #expect(withoutDepth.latestSnapshot?.depth == nil)
        let sentence = boundarySimulator().buildNMEASentences(
            talkerID: "II",
            type: .dbt,
            snapshot: withoutDepth.latestSnapshot!
        )
        #expect(sentence.isEmpty)
    }

    @Test
    func disablingTheAnemometerHidesWindAndLeavesTheTrack() {
        let start = Date(timeIntervalSince1970: 1_800_020_500)
        var published = boundaryState(seed: 8)
        var hidden = published
        let enabled = boundaryConfig(boatSpeedMode: .estimated)
        let disabled = replacing(enabled, anemometer: false)

        for step in 0...3 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&published, enabled, at: time)
            tick(&hidden, disabled, at: time)
        }

        expectSameVessel(published.vesselTruth, hidden.vesselTruth)
        #expect(published.environmentTruth.trueWindSpeedKnots == hidden.environmentTruth.trueWindSpeedKnots)
        #expect((published.vesselTruth.speedThroughWaterKnots ?? 0) > 3)
        #expect(hidden.tws.value == nil)
        #expect(hidden.twd.value == nil)
        #expect(hidden.latestSnapshot?.windSpeedTrue == nil)
        #expect(hidden.latestSnapshot?.windDirectionTrue == nil)
        #expect(published.latestSnapshot?.windSpeedTrue == published.environmentTruth.trueWindSpeedKnots)
        let hiddenSentences = SimulationEngine.activeSentenceTypes(snapshot: hidden.latestSnapshot!, config: disabled)
        #expect(hiddenSentences.contains(.mwv) == false)
        #expect(hiddenSentences.contains(.mwd) == false)
        let built = boundarySimulator().buildNMEASentences(
            talkerID: "II",
            type: .mwv,
            snapshot: hidden.latestSnapshot!
        )
        #expect(built.isEmpty)

        var restored = hidden
        let again = replacing(disabled, anemometer: true)
        let next = start.addingTimeInterval(3.05)
        tick(&published, enabled, at: next)
        tick(&restored, again, at: next)
        expectSameVessel(published.vesselTruth, restored.vesselTruth)
        #expect(restored.tws.value == restored.environmentTruth.trueWindSpeedKnots)
        #expect(restored.latestSnapshot?.windSpeedTrue == restored.environmentTruth.trueWindSpeedKnots)
        let restoredSentences = SimulationEngine.activeSentenceTypes(snapshot: restored.latestSnapshot!, config: again)
        #expect(restoredSentences.contains(.mwv))
    }

    @Test
    func aHiddenPolarStillIgnoresTheReferenceWhenTheAnemometerIsOff() {
        let start = Date(timeIntervalSince1970: 1_800_020_700)
        var extasy = boundaryState(seed: 9)
        var nimana = extasy
        extasy.hiddenPolarOverride = .beneteauFirst407
        nimana.hiddenPolarOverride = .beneteauFirst407
        let extasyConfig = replacing(boundaryConfig(boatSpeedMode: .estimated), anemometer: false)
        let nimanaConfig = replacing(extasyConfig, profile: .nimana)

        for step in 0...2 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&extasy, extasyConfig, at: time)
            tick(&nimana, nimanaConfig, at: time)
        }

        expectSameVessel(extasy.vesselTruth, nimana.vesselTruth)
        #expect(extasy.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(nimana.vesselObservation.referenceProfile == .nimana)
        #expect(nimana.latestSnapshot?.windSpeedTrue == nil)
        #expect((nimana.vesselTruth.speedThroughWaterKnots ?? 0) > 3)
    }

    @Test
    func identicalScenarioSeedsRepeatTheHeadingRedraw() {
        let start = Date(timeIntervalSince1970: 1_800_020_600)
        var first = preparedScenario(seed: 11, headingOffset: 15)
        var second = preparedScenario(seed: 11, headingOffset: 15)
        var other = preparedScenario(seed: 12, headingOffset: 15)
        for step in 0...2 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&first.state, first.config, at: time)
            tick(&second.state, second.config, at: time)
            tick(&other.state, other.config, at: time)
        }

        #expect(first.state.environmentTruth == second.state.environmentTruth)
        #expect(first.state.vesselTruth == second.state.vesselTruth)
        #expect(first.state.environmentTruth.trueWindSpeedKnots == 12)
        #expect(first.state.vesselTruth.magneticHeading != other.state.vesselTruth.magneticHeading)
    }

    @Test
    func eachSensorToggleLeavesTruthAndTimeUnchanged() {
        let start = Date(timeIntervalSince1970: 1_800_021_000)
        let enabled = allSensors(boundaryConfig(boatSpeedMode: .estimated))
        var cases: [(String, WritableKeyPath<SensorToggleStates, Bool>, (SimulationState) -> Void)] = [
            ("anemometer", \.hasAnemometer, { state in
                #expect(state.tws.value == nil)
                #expect(state.latestSnapshot?.windSpeedTrue == nil)
            }),
            ("compass", \.hasCompass, { state in
                #expect(state.heading.value == nil)
                #expect(state.latestSnapshot?.magneticHeading == nil)
            }),
            ("gyro", \.hasGyro, { state in
                #expect(state.gyroHeading.value == nil)
                #expect(state.latestSnapshot?.gyroHeading == nil)
            }),
            ("gps", \.hasGPS, { _ in }),
            ("depth", \.hasEchoSounder, { state in
                #expect(state.depth.value == nil)
                #expect(state.latestSnapshot?.depth == nil)
            }),
            ("speed log", \.hasSpeedLog, { state in
                #expect(state.speed.value == nil)
                #expect(state.latestSnapshot?.boatSpeed == nil)
            }),
            ("sea temperature", \.hasWaterTempSensor, { state in
                #expect(state.seaTemp.value == nil)
                #expect(state.latestSnapshot?.seaTemperature == nil)
            }),
            ("air temperature", \.hasAirTempSensor, { state in
                #expect(state.airTemp.value == nil)
                #expect(state.latestSnapshot?.airTemperature == nil)
            }),
            ("humidity", \.hasHumidtySensor, { state in
                #expect(state.humidity.value == nil)
                #expect(state.latestSnapshot?.relativeHumidity == nil)
            }),
            ("barometer", \.hasBarometer, { state in
                #expect(state.barometer.value == nil)
                #expect(state.latestSnapshot?.airPressure == nil)
            }),
            ("gnss", \.shouldSendGNSS, { _ in }),
            ("dsc", \.shouldSendDSC, { _ in })
        ]

        for item in cases {
            var published = boundaryState(seed: 15)
            var hidden = published
            var toggles = enabled.sensorToggles
            toggles[keyPath: item.1] = false
            let disabled = replacing(enabled, sensors: toggles)
            for step in 0...3 {
                let time = start.addingTimeInterval(TimeInterval(step))
                tick(&published, enabled, at: time)
                tick(&hidden, disabled, at: time)
            }
            #expect(published.vesselTruth == hidden.vesselTruth)
            #expect(published.environmentTruth == hidden.environmentTruth)
            #expect(published.lastSimulationTickDate == hidden.lastSimulationTickDate)
            #expect((published.vesselTruth.speedThroughWaterKnots ?? 0) > 3)
            item.2(hidden)
            #expect(suppressed(item.0, snapshot: hidden.latestSnapshot!, config: disabled))

            var restored = hidden
            let next = start.addingTimeInterval(3.05)
            tick(&published, enabled, at: next)
            tick(&restored, enabled, at: next)
            #expect(published.vesselTruth == restored.vesselTruth)
            #expect(published.environmentTruth == restored.environmentTruth)
            #expect(restoredMeasurement(item.0, state: restored, config: enabled))
        }
    }

    @Test
    func aDisabledSpeedLogStillRedrawsManualSpeed() {
        let start = Date(timeIntervalSince1970: 1_800_021_100)
        var published = boundaryState(seed: 16, speedOffset: 2)
        var hidden = published
        let enabled = allSensors(boundaryConfig(boatSpeedMode: .manual, speedOffset: 2))
        var toggles = enabled.sensorToggles
        toggles.hasSpeedLog = false
        let disabled = replacing(enabled, sensors: toggles)
        for step in 0...2 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&published, enabled, at: time)
            tick(&hidden, disabled, at: time)
        }
        #expect(published.vesselTruth == hidden.vesselTruth)
        #expect(published.latestSnapshot?.boatSpeed == published.vesselTruth.speedThroughWaterKnots)
        #expect(hidden.speed.value == nil)
        #expect(hidden.latestSnapshot?.boatSpeed == nil)
    }

    @Test
    func aManeuverKeepsTheSameHeadingWhenTheCompassAndGyroAreOff() {
        let start = Date(timeIntervalSince1970: 1_800_021_200)
        var published = boundaryState(seed: 17)
        var hidden = published
        let maneuver = ActiveManeuver(
            kind: .tack,
            side: .port,
            startedAt: start,
            duration: 8,
            fromTrueHeading: 90,
            toTrueHeading: 270,
            trueWindDirection: 180,
            turnDelta: 180,
            drivesHeading: true
        )
        published.activeManeuver = maneuver
        hidden.activeManeuver = maneuver
        let enabled = allSensors(boundaryConfig(boatSpeedMode: .estimated))
        var toggles = enabled.sensorToggles
        toggles.hasCompass = false
        toggles.hasGyro = false
        let disabled = replacing(enabled, sensors: toggles)
        for step in [0.0, 2.0, 4.0, 8.0] {
            let time = start.addingTimeInterval(step)
            tick(&published, enabled, at: time)
            tick(&hidden, disabled, at: time)
        }
        #expect(published.vesselTruth == hidden.vesselTruth)
        #expect(hidden.heading.value == nil)
        #expect(hidden.gyroHeading.value == nil)
        #expect(abs(published.vesselTruth.trueHeading - 270) < 0.001)
    }

    @Test
    func hiddenPolarIndependenceHoldsWithEverySensorOff() {
        let start = Date(timeIntervalSince1970: 1_800_021_300)
        var extasy = boundaryState(seed: 18)
        var nimana = extasy
        extasy.hiddenPolarOverride = .beneteauFirst407
        nimana.hiddenPolarOverride = .beneteauFirst407
        let base = replacing(boundaryConfig(boatSpeedMode: .estimated), sensors: SensorToggleStates(
            hasAnemometer: false,
            hasCompass: false,
            hasGyro: false,
            hasGPS: false,
            hasEchoSounder: false,
            hasSpeedLog: false,
            hasWaterTempSensor: false,
            hasAirTempSensor: false,
            hasHumidtySensor: false,
            hasBarometer: false
        ))
        let other = replacing(base, profile: .nimana)
        for step in 0...2 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&extasy, base, at: time)
            tick(&nimana, other, at: time)
        }
        #expect(extasy.vesselTruth == nimana.vesselTruth)
        #expect(extasy.environmentTruth == nimana.environmentTruth)
        #expect((nimana.vesselTruth.speedThroughWaterKnots ?? 0) > 3)
        #expect(nimana.vesselObservation.referenceProfile == .nimana)
    }
}

private struct BoundaryRuntime {
    var state: SimulationState
    var config: SimulationConfig
}

private final class BoundaryStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    func loadDocument() throws -> VesselProfileDocument? { document }
    func saveDocument(_ document: VesselProfileDocument) throws { self.document = document }
}

private func boundarySimulator() -> NMEASimulator {
    let suite = "MeasurementBoundary.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults, vesselStore: BoundaryStore())
    simulator.outputEndpoints[0].isEnabled = false
    simulator.weatherSourceMode = .manual
    simulator.boatProfile = .beneteauFirst407
    simulator.mwvReferenceMode = .trueReference
    simulator.sensorToggles.hasGyro = false
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasGPS = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasEchoSounder = true
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    simulator.depth = SimulatedValue(type: .depth, center: 20, offset: 0, value: 20)
    simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
    return simulator
}

private func boundaryState(
    seed: UInt64,
    windSpeedOffset: Double = 0,
    headingOffset: Double = 0,
    speedOffset: Double = 0
) -> SimulationState {
    let simulator = boundarySimulator()
    simulator.tws.offset = windSpeedOffset
    simulator.heading.offset = headingOffset
    simulator.speed.offset = speedOffset
    var state = SimulationState(from: simulator)
    state.enableExperimentRandomness(seed: seed)
    return state
}

private func boundaryConfig(
    windSpeedOffset: Double = 0,
    headingOffset: Double = 0,
    boatSpeedMode: BoatSpeedMode = .manual,
    speedOffset: Double = 0
) -> SimulationConfig {
    let simulator = boundarySimulator()
    simulator.boatSpeedMode = boatSpeedMode
    simulator.tws.offset = windSpeedOffset
    simulator.heading.offset = headingOffset
    simulator.speed.offset = speedOffset
    return simulator.captureSimulationConfig()
}

private func preparedScenario(seed: UInt64, headingOffset: Double) -> BoundaryRuntime {
    var baseline = ExperimentRuntime(state: boundaryState(seed: 1, headingOffset: headingOffset), config: boundaryConfig(headingOffset: headingOffset))
    baseline.state.disableExperimentRandomness()
    let scenario = ExperimentScenario(
        name: "Boundary",
        seed: seed,
        referencePolarProfile: .beneteauFirst407,
        hiddenPolarProfile: .beneteauFirst407,
        windProgram: .steady(trueWindDirectionDegrees: 180, speedKnots: 12),
        durationSeconds: 60,
        sampleIntervalSeconds: 1
    )
    let prepared = ExperimentScenarioRunner.prepare(scenario, from: baseline)
    return BoundaryRuntime(state: prepared.state, config: prepared.config)
}

private func tick(_ state: inout SimulationState, _ config: SimulationConfig, at timestamp: Date) {
    _ = SimulationEngine.tickSimulation(
        state: &state,
        config: config,
        at: timestamp,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
}

private func expectedSample(seed: UInt64, draw: Int, center: Double, offset: Double, range: ClosedRange<Double>) -> Double {
    var generator = ExperimentRandomGenerator(seed: seed)
    var unit = 0.0
    for _ in 0...draw {
        unit = generator.nextUnitInterval()
    }
    let lower = max(range.lowerBound, center - offset)
    let upper = min(range.upperBound, center + offset)
    return lower + (upper - lower) * unit.clamped(to: 0...1)
}

private func allSensors(_ config: SimulationConfig) -> SimulationConfig {
    var sensors = config.sensorToggles
    sensors.hasAnemometer = true
    sensors.hasCompass = true
    sensors.hasGyro = true
    sensors.hasGPS = true
    sensors.hasEchoSounder = true
    sensors.hasSpeedLog = true
    sensors.hasWaterTempSensor = true
    sensors.hasAirTempSensor = true
    sensors.hasHumidtySensor = true
    sensors.hasBarometer = true
    return replacing(config, sensors: sensors)
}

private func suppressed(_ name: String, snapshot: SimulationSnapshot, config: SimulationConfig) -> Bool {
    let types = SimulationEngine.activeSentenceTypes(snapshot: snapshot, config: config)
    switch name {
    case "anemometer":
        return !types.contains(.mwv) && !types.contains(.mwd)
    case "compass":
        return !types.contains(.hdg)
    case "gyro":
        return !types.contains(.hdt) && !types.contains(.rot)
    case "gps":
        return !types.contains(.rmc) && !types.contains(.gga) && !types.contains(.vtg)
    case "depth":
        return !types.contains(.dbt) && !types.contains(.dpt)
    case "speed log":
        return !types.contains(.vlw) && !types.contains(.vhw)
    case "sea temperature":
        return !types.contains(.mtw)
    default:
        return true
    }
}

private func restoredMeasurement(_ name: String, state: SimulationState, config: SimulationConfig) -> Bool {
    let types = SimulationEngine.activeSentenceTypes(snapshot: state.latestSnapshot!, config: config)
    switch name {
    case "anemometer":
        return state.latestSnapshot?.windSpeedTrue != nil && types.contains(.mwv)
    case "compass":
        return state.latestSnapshot?.magneticHeading != nil && types.contains(.hdg)
    case "gyro":
        return state.latestSnapshot?.gyroHeading != nil && types.contains(.hdt)
    case "gps":
        return types.contains(.rmc)
    case "depth":
        return state.latestSnapshot?.depth != nil && types.contains(.dbt)
    case "speed log":
        return state.latestSnapshot?.boatSpeed != nil && types.contains(.vlw)
    case "sea temperature":
        return state.latestSnapshot?.seaTemperature != nil && types.contains(.mtw)
    case "air temperature":
        return state.latestSnapshot?.airTemperature != nil
    case "humidity":
        return state.latestSnapshot?.relativeHumidity != nil
    case "barometer":
        return state.latestSnapshot?.airPressure != nil
    default:
        return true
    }
}

private func expectSameVessel(_ lhs: VesselTruth, _ rhs: VesselTruth) {
    #expect(lhs.latitude == rhs.latitude)
    #expect(lhs.longitude == rhs.longitude)
    #expect(lhs.trueHeading == rhs.trueHeading)
    #expect(lhs.speedThroughWaterKnots == rhs.speedThroughWaterKnots)
    #expect(lhs.speedOverGroundKnots == rhs.speedOverGroundKnots)
    #expect(lhs.courseOverGroundDegrees == rhs.courseOverGroundDegrees)
}

private func replacing(
    _ config: SimulationConfig,
    faults: FaultInjectionSettings? = nil,
    echoSounder: Bool? = nil,
        anemometer: Bool? = nil,
        profile: BoatProfile? = nil,
        sensors override: SensorToggleStates? = nil
) -> SimulationConfig {
    var sensors = override ?? config.sensorToggles
    if override == nil {
        if let echoSounder { sensors.hasEchoSounder = echoSounder }
        if let anemometer { sensors.hasAnemometer = anemometer }
    }
    return SimulationConfig(
        sensorToggles: sensors,
        sentenceToggles: config.sentenceToggles,
        interval: config.interval,
        sentenceIntervals: config.sentenceIntervals,
        weatherSourceMode: config.weatherSourceMode,
        latestLiveWeather: config.latestLiveWeather,
        boatSpeedMode: config.boatSpeedMode,
        boatProfile: profile ?? config.boatProfile,
        waypointNavigation: config.waypointNavigation,
        tackAnimationInProgress: config.tackAnimationInProgress,
        maneuverSettings: config.maneuverSettings,
        talkerID: config.talkerID,
        perSentenceTalkerID: config.perSentenceTalkerID,
        depthOffsetMeters: config.depthOffsetMeters,
        faultInjection: faults ?? config.faultInjection,
        mwvReferenceMode: config.mwvReferenceMode,
        enabledOutputEndpoints: config.enabledOutputEndpoints
    )
}
