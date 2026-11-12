import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct PolarDynamicsTests {

    @Test
    func instantModeMatchesTheFirst407Polar() {
        let (_, speed) = settledInstantSpeed(profile: .beneteauFirst407)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: 90
        ) ?? -1
        #expect(abs(speed - polar) < 0.000_001)
        #expect(PolarModel(profile: .beneteauFirst407).targetSpeedKnots(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: 90
        ) == Optional(polar))
    }

    @Test
    func switchingBoatProfileKeepsReferenceAndHiddenTogether() {
        var rig = PolarRig()
        let t0 = rig.time
        _ = tick(&rig, at: t0)
        #expect(rig.state.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(SimulationEngine.hiddenPolar(for: rig.state, config: rig.config).profile == .beneteauFirst407)
        let first = rig.state.vesselTruth.speedThroughWaterKnots ?? 0

        rig.config = replacing(rig.config, profile: .nimana)
        _ = tick(&rig, at: t0.addingTimeInterval(0.05))
        let held = rig.state.vesselTruth.speedThroughWaterKnots ?? 0
        #expect(rig.state.vesselObservation.referenceProfile == .nimana)
        #expect(SimulationEngine.hiddenPolar(for: rig.state, config: rig.config).profile == .nimana)
        #expect(abs(held - first) < 0.000_001)
        #expect(rig.state.hiddenPolarOverride == nil)
    }

    @Test
    func researchOverrideStaysPutWhenTheSelectedProfileChanges() {
        var rig = PolarRig()
        rig.state.hiddenPolarOverride = .nimana
        _ = tick(&rig, at: rig.time)
        #expect(rig.state.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(SimulationEngine.hiddenPolar(for: rig.state, config: rig.config).profile == .nimana)

        rig.config = replacing(rig.config, profile: .nimana)
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.05))
        #expect(rig.state.vesselObservation.referenceProfile == .nimana)
        #expect(rig.state.hiddenPolarOverride == .nimana)
        #expect(SimulationEngine.hiddenPolar(for: rig.state, config: rig.config).profile == .nimana)
    }

    @Test
    func firstOrderAcceleratesAndDeceleratesFromTheCurrentSpeed() {
        var rig = PolarRig()
        _ = tick(&rig, at: rig.time)
        let target = rig.state.vesselTruth.speedThroughWaterKnots ?? 0
        rig.state.performance.speedResponse = .firstOrder
        rig.state.performance.accelerationTimeConstantSeconds = 8
        rig.state.performance.decelerationTimeConstantSeconds = 4
        rig.state.vesselTruth.speedThroughWaterKnots = 1
        rig.state.lastSimulationTickDate = rig.time
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.5))
        let accelerated = SimulationEngine.stepSpeed(current: 1, target: target, deltaTime: 0.5, tau: 8)
        #expect(abs((rig.state.vesselTruth.speedThroughWaterKnots ?? 0) - accelerated) < 0.000_001)
        #expect((rig.state.vesselTruth.speedThroughWaterKnots ?? 0) > 1)
        #expect((rig.state.vesselTruth.speedThroughWaterKnots ?? 0) < target)

        rig.state.vesselTruth.speedThroughWaterKnots = target + 4
        rig.state.lastSimulationTickDate = rig.time.addingTimeInterval(0.5)
        rig.state.lastSensorEvolutionDate = rig.time.addingTimeInterval(1)
        _ = tick(&rig, at: rig.time.addingTimeInterval(1.0))
        let decelerated = SimulationEngine.stepSpeed(current: target + 4, target: target, deltaTime: 0.5, tau: 4)
        #expect(abs((rig.state.vesselTruth.speedThroughWaterKnots ?? 0) - decelerated) < 0.000_001)
    }

    @Test
    func firstOrderStepsMatchOneDoubleStep() {
        let once = SimulationEngine.stepSpeed(
            current: SimulationEngine.stepSpeed(current: 3, target: 8, deltaTime: 0.5, tau: 4),
            target: 8,
            deltaTime: 0.5,
            tau: 4
        )
        let doubled = SimulationEngine.stepSpeed(current: 3, target: 8, deltaTime: 1, tau: 4)
        #expect(abs(once - doubled) < 0.000_000_001)
    }

    @Test
    func parameterChangesKeepSpeedThroughWaterInFirstOrderAndJumpInInstantMode() {
        var rig = PolarRig()
        _ = tick(&rig, at: rig.time)
        let full = rig.state.vesselTruth.speedThroughWaterKnots ?? 0
        rig.state.performance.speedResponse = .firstOrder
        rig.state.performance.accelerationTimeConstantSeconds = 30
        rig.state.vesselTruth.speedThroughWaterKnots = 3
        rig.state.lastSimulationTickDate = rig.time
        var reduced = PerformanceParameters()
        reduced.speedResponse = .firstOrder
        reduced.accelerationTimeConstantSeconds = 30
        reduced.hullFactor = 0.5
        rig.state.scheduledPerformanceChanges = [
            ScheduledPerformanceChange(simulationTime: rig.time.addingTimeInterval(0.05), parameters: reduced)
        ]
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.05))
        let afterChange = rig.state.vesselTruth.speedThroughWaterKnots ?? 0
        #expect(rig.state.performance.hullFactor == 0.5)
        #expect(abs(afterChange - 3) < 0.2)
        #expect(afterChange > 2)
        #expect(afterChange < full)

        var instant = PolarRig()
        _ = tick(&instant, at: instant.time)
        var half = PerformanceParameters()
        half.hullFactor = 0.5
        instant.state.scheduledPerformanceChanges = [
            ScheduledPerformanceChange(simulationTime: instant.time.addingTimeInterval(0.05), parameters: half)
        ]
        _ = tick(&instant, at: instant.time.addingTimeInterval(0.05))
        #expect(abs((instant.state.vesselTruth.speedThroughWaterKnots ?? 0) - full * 0.5) < 0.000_001)
    }

    @Test
    func timestampedChangesApplyInOrderAndDropInvalidTimes() {
        var rig = PolarRig()
        rig.state.performance.speedResponse = .firstOrder
        rig.state.performance.accelerationTimeConstantSeconds = 60
        rig.state.vesselTruth.speedThroughWaterKnots = 4
        rig.state.lastSimulationTickDate = rig.time
        var early = PerformanceParameters()
        early.speedResponse = .firstOrder
        early.accelerationTimeConstantSeconds = 60
        early.hullFactor = 0.8
        var later = early
        later.hullFactor = 0.4
        rig.state.scheduledPerformanceChanges = [
            ScheduledPerformanceChange(
                simulationTime: Date(timeIntervalSinceReferenceDate: .nan),
                parameters: later
            ),
            ScheduledPerformanceChange(
                simulationTime: Date(timeIntervalSinceReferenceDate: .infinity),
                parameters: later
            ),
            ScheduledPerformanceChange(simulationTime: rig.time.addingTimeInterval(10), parameters: later),
            ScheduledPerformanceChange(simulationTime: rig.time.addingTimeInterval(-1), parameters: early)
        ]
        _ = tick(&rig, at: rig.time)
        #expect(rig.state.performance.hullFactor == 0.8)
        #expect(rig.state.scheduledPerformanceChanges.count == 1)
        #expect(abs((rig.state.vesselTruth.speedThroughWaterKnots ?? 0) - 4) < 0.05)
        _ = tick(&rig, at: rig.time.addingTimeInterval(10))
        #expect(rig.state.performance.hullFactor == 0.4)
        #expect(rig.state.scheduledPerformanceChanges.isEmpty)
    }

    @Test
    func invalidPerformanceValuesAreNormalizedWithoutAJump() {
        var rig = PolarRig()
        _ = tick(&rig, at: rig.time)
        rig.state.performance.speedResponse = .firstOrder
        rig.state.performance.hullFactor = .nan
        rig.state.performance.sailFactor = -2
        rig.state.performance.trimEfficiency = .infinity
        rig.state.performance.accelerationTimeConstantSeconds = .nan
        rig.state.performance.decelerationTimeConstantSeconds = 60
        rig.state.performance.tackSpeedRetention = 4
        rig.state.vesselTruth.speedThroughWaterKnots = 5
        rig.state.lastSimulationTickDate = rig.time
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.05))
        #expect(rig.state.performance.hullFactor == 1)
        #expect(rig.state.performance.sailFactor == 0)
        #expect(rig.state.performance.trimEfficiency == 1)
        #expect(rig.state.performance.accelerationTimeConstantSeconds == 8)
        #expect(rig.state.performance.tackSpeedRetention == 1)
        #expect(abs((rig.state.vesselTruth.speedThroughWaterKnots ?? 0) - 5) < 0.05)
    }

    @Test
    func tackAndGybeAreClassifiedFromTheShortArcIncludingAcrossNorth() {
        #expect(SimulationEngine.classifyManeuver(fromHeading: 140, toHeading: 220, trueWindDirection: 180) == .tack)
        #expect(SimulationEngine.classifyManeuver(fromHeading: 40, toHeading: 320, trueWindDirection: 180) == .gybe)
        #expect(SimulationEngine.classifyManeuver(fromHeading: 350, toHeading: 10, trueWindDirection: 0) == .tack)
        #expect(SimulationEngine.classifyManeuver(fromHeading: 350, toHeading: 10, trueWindDirection: 180) == .gybe)
        #expect(SimulationEngine.classifyManeuver(fromHeading: 0, toHeading: 20, trueWindDirection: 90) == nil)
        #expect(SimulationEngine.classifyManeuver(fromHeading: 10, toHeading: 30, trueWindDirection: 10) == nil)
    }

    @Test
    func windShiftAndSmallHeadingChangeStayIdle() {
        var rig = PolarRig()
        _ = tick(&rig, at: rig.time)
        rig.state.twd.centerValue = 210
        rig.state.lastSensorEvolutionDate = rig.time.addingTimeInterval(-2)
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.05))
        #expect(rig.state.vesselObservation.maneuverPhase == .idle)
        #expect(rig.state.vesselObservation.maneuverKind == nil)

        rig.state.heading.centerValue = normalizeAngle((rig.state.heading.centerValue) + 15)
        rig.state.lastSensorEvolutionDate = rig.time.addingTimeInterval(-2)
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.1))
        #expect(rig.state.vesselObservation.maneuverPhase == .idle)
    }

    @Test
    func maneuverLossDependsOnKindAndRecoveryReturnsToIdle() {
        var tack = PolarRig()
        _ = tick(&tack, at: tack.time)
        let full = tack.state.vesselTruth.speedThroughWaterKnots ?? 0
        tack.state.performance.tackSpeedRetention = 0.5
        tack.state.performance.gybeSpeedRetention = 1
        tack.state.activeManeuver = ActiveManeuver(
            kind: .tack,
            startedAt: tack.time,
            duration: 10,
            fromTrueHeading: 140,
            toTrueHeading: 220,
            trueWindDirection: 180
        )
        tack.config = replacing(tack.config, tack: true)
        tack.state.lastSensorEvolutionDate = tack.time.addingTimeInterval(5)
        _ = tick(&tack, at: tack.time.addingTimeInterval(5))
        #expect(tack.state.vesselObservation.maneuverPhase == .inProgress)
        #expect(tack.state.vesselObservation.maneuverKind == .tack)
        #expect(abs((tack.state.vesselTruth.speedThroughWaterKnots ?? 0) - full * 0.5) < 0.000_001)

        var gybe = PolarRig()
        _ = tick(&gybe, at: gybe.time)
        gybe.state.performance.tackSpeedRetention = 1
        gybe.state.performance.gybeSpeedRetention = 0.5
        gybe.state.activeManeuver = ActiveManeuver(
            kind: .gybe,
            startedAt: gybe.time,
            duration: 10,
            fromTrueHeading: 40,
            toTrueHeading: 320,
            trueWindDirection: 180
        )
        gybe.config = replacing(gybe.config, tack: true)
        gybe.state.lastSensorEvolutionDate = gybe.time.addingTimeInterval(5)
        _ = tick(&gybe, at: gybe.time.addingTimeInterval(5))
        #expect(gybe.state.vesselObservation.maneuverKind == .gybe)
        #expect(abs((gybe.state.vesselTruth.speedThroughWaterKnots ?? 0) - full * 0.5) < 0.000_001)

        tack.config = replacing(tack.config, tack: false)
        tack.state.lastSensorEvolutionDate = tack.time.addingTimeInterval(5.2)
        _ = tick(&tack, at: tack.time.addingTimeInterval(5.05))
        #expect(tack.state.vesselObservation.maneuverPhase == .recovery)
        #expect(tack.state.vesselObservation.maneuverKind == .tack)
        #expect(abs((tack.state.vesselTruth.speedThroughWaterKnots ?? 0) - full) < 0.000_001)
        _ = tick(&tack, at: tack.time.addingTimeInterval(5.2))
        #expect(tack.state.vesselObservation.maneuverPhase == .idle)
        #expect(tack.state.vesselObservation.maneuverKind == nil)
    }

    @Test
    func sailConfigurationSerializesAndDoesNotChangeSpeed() throws {
        let sail = SailConfiguration(
            mainSailID: "11111111-1111-1111-1111-111111111111",
            headsailID: "22222222-2222-2222-2222-222222222222",
            downwindSailID: "33333333-3333-3333-3333-333333333333",
            mainsailReef: .reef2
        )
        let data = try JSONEncoder().encode(sail)
        let decoded = try JSONDecoder().decode(SailConfiguration.self, from: data)
        #expect(decoded == sail)

        var rig = PolarRig()
        _ = tick(&rig, at: rig.time)
        let speed = rig.state.vesselTruth.speedThroughWaterKnots
        rig.state.sailConfiguration = sail
        _ = tick(&rig, at: rig.time.addingTimeInterval(0.05))
        #expect(rig.state.vesselTruth.speedThroughWaterKnots == speed)
        #expect(rig.state.vesselObservation.sailConfiguration == sail)

        let mismatches = SailPerformanceConsistency.mismatchedSailIDs(
            configuration: sail,
            performanceTagBySailID: [sail.mainSailID!: "inventory-a", sail.headsailID!: "inventory-b"],
            activePerformanceTag: "inventory-a"
        )
        #expect(mismatches == [sail.headsailID!])
        #expect(rig.state.vesselTruth.speedThroughWaterKnots == speed)
    }

    @Test
    func hiddenModelIsAbsentFromTheObservationChannel() {
        var rig = PolarRig()
        rig.state.hiddenPolarOverride = .nimana
        rig.state.performance.hullFactor = 0.7
        rig.state.sailConfiguration.mainSailID = "main-sail"
        let snapshot = tick(&rig, at: rig.time)
        let mirror = SimulationInputMirror(from: rig.simulator)

        #expect(rig.state.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(SimulationEngine.hiddenPolar(for: rig.state, config: rig.config).profile == .nimana)
        #expect(channelLabels(rig.state.vesselObservation).contains("hidden") == false)
        #expect(channelLabels(snapshot).contains("hidden") == false)
        #expect(channelLabels(mirror).contains("hidden") == false)
        #expect(channelLabels(mirror).contains("hullfactor") == false)
        let visible = String(reflecting: rig.state.vesselObservation) + String(reflecting: snapshot)
        #expect(!visible.contains("nimana"))
        #expect(visible.contains("main-sail"))
    }

    @Test @MainActor
    func gybeManeuverStartsTheExistingHeadingAnimation() {
        let rig = PolarRig()
        rig.simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 40, offset: 0, value: 40)
        rig.simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
        rig.simulator.syncInputMirror()
        rig.simulator.transmitRuntime = SimulationState(from: rig.simulator)
        defer { rig.simulator.stopSimulation() }
        rig.simulator.beginGybeManeuver()
        #expect(rig.simulator.tackAnimationInProgress)
        let kind = rig.simulator.simulationQueue.sync { rig.simulator.transmitRuntime?.activeManeuver?.kind }
        #expect(kind == .gybe)
    }

    @Test
    func repeatedTicksWithTheSameClockMatch() {
        var first = PolarRig()
        var second = PolarRig()
        _ = tick(&first, at: first.time)
        _ = tick(&second, at: second.time)
        _ = tick(&first, at: first.time.addingTimeInterval(0.05))
        _ = tick(&second, at: second.time.addingTimeInterval(0.05))
        #expect(first.state.vesselTruth.speedThroughWaterKnots == second.state.vesselTruth.speedThroughWaterKnots)
        #expect(first.state.gpsData.latitude == second.state.gpsData.latitude)
    }
}

private struct PolarRig {
    var simulator: NMEASimulator
    var state: SimulationState
    var config: SimulationConfig
    var time = Date(timeIntervalSince1970: 1_800_003_000)

    init(profile: BoatProfile = .beneteauFirst407) {
        let suite = "PolarDynamics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults)
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.weatherSourceMode = .manual
        simulator.boatSpeedMode = .estimated
        simulator.boatProfile = profile
        simulator.interval = 1
        simulator.sensorToggles.hasGyro = true
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasGPS = true
        simulator.sensorToggles.hasSpeedLog = true
        simulator.sensorToggles.hasAnemometer = true
        let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
        let magnetic = normalizeAngle(90 - variation)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
        simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
        self.simulator = simulator
        self.state = SimulationState(from: simulator)
        self.config = simulator.captureSimulationConfig()
    }
}

private func tick(_ rig: inout PolarRig, at time: Date) -> SimulationSnapshot {
    SimulationEngine.tickSimulation(
        state: &rig.state,
        config: rig.config,
        at: time,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
}

private func settledInstantSpeed(profile: BoatProfile) -> (PolarRig, speed: Double) {
    var rig = PolarRig(profile: profile)
    _ = tick(&rig, at: rig.time)
    return (rig, rig.state.vesselTruth.speedThroughWaterKnots ?? 0)
}

private func replacing(_ config: SimulationConfig, profile: BoatProfile? = nil, tack: Bool? = nil) -> SimulationConfig {
    SimulationConfig(
        sensorToggles: config.sensorToggles,
        sentenceToggles: config.sentenceToggles,
        interval: config.interval,
        sentenceIntervals: config.sentenceIntervals,
        weatherSourceMode: config.weatherSourceMode,
        latestLiveWeather: config.latestLiveWeather,
        boatSpeedMode: config.boatSpeedMode,
        boatProfile: profile ?? config.boatProfile,
        waypointNavigation: config.waypointNavigation,
        tackAnimationInProgress: tack ?? config.tackAnimationInProgress,
        maneuverSettings: config.maneuverSettings,
        talkerID: config.talkerID,
        perSentenceTalkerID: config.perSentenceTalkerID,
        depthOffsetMeters: config.depthOffsetMeters,
        faultInjection: config.faultInjection,
        mwvReferenceMode: config.mwvReferenceMode,
        enabledOutputEndpoints: config.enabledOutputEndpoints
    )
}

private func channelLabels(_ value: Any) -> String {
    var names: [String] = []
    func walk(_ value: Any) {
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            if let label = child.label {
                names.append(label.lowercased())
            }
            walk(child.value)
        }
    }
    walk(value)
    return names.joined(separator: " ")
}
