import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct ExperimentScenarioRunnerTests {

    @Test
    func identicalSeedsAndBaselinesProduceTheSameRun() {
        let scenario = experimentScenario(seed: 11)
        var first = ExperimentScenarioRunner.prepare(scenario, from: experimentBaseline())
        var second = ExperimentScenarioRunner.prepare(scenario, from: experimentBaseline())
        let start = Date(timeIntervalSince1970: 1_800_010_000)

        for step in 0...2 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&first, at: time)
            tick(&second, at: time)
        }

        #expect(first.state.environmentTruth == second.state.environmentTruth)
        #expect(first.state.vesselTruth == second.state.vesselTruth)
        #expect(first.state.vesselObservation == second.state.vesselObservation)
        #expect(first.state.latestSnapshot?.windSpeedTrue == second.state.latestSnapshot?.windSpeedTrue)
        #expect(first.state.latestSnapshot?.boatSpeed == second.state.latestSnapshot?.boatSpeed)
    }

    @Test
    func steadyWindIsAppliedAndKeptInManualMode() {
        let scenario = experimentScenario(seed: 3, direction: 180, speed: 12)
        var runtime = ExperimentScenarioRunner.prepare(scenario, from: experimentBaseline())

        #expect(runtime.config.weatherSourceMode == .manual)
        #expect(runtime.config.boatSpeedMode == .estimated)
        #expect(runtime.state.environmentTruth.trueWindDirection == 180)
        #expect(runtime.state.environmentTruth.trueWindSpeedKnots == 12)
        #expect(runtime.state.twd.offset == 0)
        #expect(runtime.state.tws.offset == 0)

        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_010_000))
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_010_001))

        #expect(runtime.state.environmentTruth.trueWindDirection == 180)
        #expect(runtime.state.environmentTruth.trueWindSpeedKnots == 12)
        #expect(runtime.state.latestSnapshot?.windDirectionTrue == 180)
        #expect(runtime.state.latestSnapshot?.windSpeedTrue == 12)
    }

    @Test
    func referenceAndHiddenPolarsStaySeparated() {
        let scenario = experimentScenario(seed: 5, reference: .beneteauFirst407, hidden: .nimana)
        var runtime = ExperimentScenarioRunner.prepare(scenario, from: experimentBaseline())

        #expect(runtime.config.boatProfile == .beneteauFirst407)
        #expect(runtime.state.hiddenPolarOverride == .nimana)
        #expect(runtime.state.vesselObservation.referenceProfile == .beneteauFirst407)

        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_010_000))

        #expect(runtime.state.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(runtime.state.latestSnapshot?.boatSpeed == 6)
        #expect(runtime.state.vesselTruth.speedThroughWaterKnots == 6)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? 0
        #expect(abs((runtime.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar) > 0.5)

        let published = publishedText(runtime)
        #expect(published.contains("nimana") == false)
        #expect(published.contains("hidden") == false)
        #expect(published.contains("$IIMWV,90,T,12.0,N,A"))
    }

    @Test
    func hiddenExtasySetsTruthWhenTheReferenceIsNimana() {
        let scenario = experimentScenario(seed: 8, reference: .nimana, hidden: .beneteauFirst407, direction: 180, speed: 12)
        var runtime = ExperimentScenarioRunner.prepare(scenario, from: experimentBaseline())
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_010_000))

        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(runtime.config.boatProfile == .nimana)
        #expect(runtime.state.hiddenPolarOverride == .beneteauFirst407)
        #expect(runtime.state.vesselObservation.referenceProfile == .nimana)
        #expect(abs((runtime.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar) < 0.000_001)
        #expect(publishedText(runtime).contains("beneteauFirst407") == false)
    }

    @Test
    func referenceChoiceDoesNotChangeAnExtasyTruthTrajectory() {
        let start = Date(timeIntervalSince1970: 1_800_010_000)
        var extasyReference = ExperimentScenarioRunner.prepare(
            experimentScenario(seed: 21, reference: .beneteauFirst407, hidden: .beneteauFirst407),
            from: experimentBaseline()
        )
        var nimanaReference = ExperimentScenarioRunner.prepare(
            experimentScenario(seed: 21, reference: .nimana, hidden: .beneteauFirst407),
            from: experimentBaseline()
        )
        for step in 0...3 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&extasyReference, at: time)
            tick(&nimanaReference, at: time)
        }

        expectSameCourse(extasyReference.state.vesselTruth, nimanaReference.state.vesselTruth)
        #expect(extasyReference.state.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(nimanaReference.state.vesselObservation.referenceProfile == .nimana)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs((extasyReference.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar) < 0.000_001)
    }

    @Test
    func referenceChoiceDoesNotChangeAHeldNimanaTruthTrajectory() {
        let start = Date(timeIntervalSince1970: 1_800_010_000)
        func prepared(reference: BoatProfile) -> ExperimentRuntime {
            var baseline = experimentBaseline()
            baseline.state.vesselTruth.speedThroughWaterKnots = 6
            baseline.state.speed.value = 6
            baseline.state.gpsData.speedOverGround = 2
            baseline.state.vesselTruth.speedOverGroundKnots = 2
            return ExperimentScenarioRunner.prepare(
                experimentScenario(seed: 22, reference: reference, hidden: .nimana),
                from: baseline
            )
        }
        var extasyReference = prepared(reference: .beneteauFirst407)
        var nimanaReference = prepared(reference: .nimana)
        for step in 0...3 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&extasyReference, at: time)
            tick(&nimanaReference, at: time)
        }

        expectSameCourse(extasyReference.state.vesselTruth, nimanaReference.state.vesselTruth)
        #expect(extasyReference.state.vesselTruth.speedThroughWaterKnots == 6)
        #expect(extasyReference.state.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(nimanaReference.state.vesselObservation.referenceProfile == .nimana)
        #expect(publishedText(extasyReference).contains("nimana") == false)
    }

    @Test
    func anUnpreparedNimanaTickHoldsSpeedThroughWater() {
        var runtime = experimentBaseline()
        runtime.config = replacingProfile(runtime.config, profile: .nimana)
        runtime.state.vesselTruth.speedThroughWaterKnots = 6
        runtime.state.speed.value = 6
        runtime.state.gpsData.speedOverGround = 2
        runtime.state.twd.value = 180
        runtime.state.tws.value = 12
        #expect(runtime.state.hiddenPolarOverride == nil)

        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_010_000))

        #expect(runtime.state.vesselTruth.speedThroughWaterKnots == 6)
        #expect(runtime.state.vesselObservation.referenceProfile == .nimana)
        #expect(runtime.state.hiddenPolarOverride == nil)
    }

    @Test
    func hiddenExtasyKeepsFirstOrderResponseAndManeuverRetention() {
        let start = Date(timeIntervalSince1970: 1_800_010_000)
        var runtime = ExperimentScenarioRunner.prepare(
            experimentScenario(seed: 23, reference: .nimana, hidden: .beneteauFirst407),
            from: experimentBaseline()
        )
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        runtime.state.performance.speedResponse = .firstOrder
        runtime.state.performance.accelerationTimeConstantSeconds = 8
        runtime.state.vesselTruth.speedThroughWaterKnots = 1
        runtime.state.lastSimulationTickDate = start
        runtime.state.lastSensorEvolutionDate = start
        tick(&runtime, at: start.addingTimeInterval(0.5))
        let accelerated = SimulationEngine.stepSpeed(current: 1, target: polar, deltaTime: 0.5, tau: 8)
        #expect(abs((runtime.state.vesselTruth.speedThroughWaterKnots ?? 0) - accelerated) < 0.000_001)

        runtime.state.performance.speedResponse = .instant
        runtime.state.performance.tackSpeedRetention = 0.5
        runtime.state.activeManeuver = ActiveManeuver(
            kind: .tack,
            startedAt: start,
            duration: 10,
            fromTrueHeading: 90,
            toTrueHeading: 270,
            trueWindDirection: 180
        )
        runtime.config = replacingProfile(runtime.config, tack: true)
        runtime.state.lastSimulationTickDate = start.addingTimeInterval(0.5)
        runtime.state.lastSensorEvolutionDate = start.addingTimeInterval(5)
        tick(&runtime, at: start.addingTimeInterval(5))
        #expect(runtime.state.vesselObservation.maneuverPhase == .inProgress)
        #expect(abs((runtime.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar * 0.5) < 0.000_001)
        #expect(runtime.state.vesselObservation.referenceProfile == .nimana)
    }

    @Test
    func declaredCurrentDoesNotMoveTheBoat() {
        var calm = ExperimentScenarioRunner.prepare(experimentScenario(seed: 9), from: experimentBaseline())
        var drifting = ExperimentScenarioRunner.prepare(
            experimentScenario(seed: 9, current: ExperimentCurrentProgram(setDegrees: 90, driftKnots: 4)),
            from: experimentBaseline()
        )
        let start = Date(timeIntervalSince1970: 1_800_010_000)
        for step in 0...3 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&calm, at: time)
            tick(&drifting, at: time)
        }

        #expect(drifting.state.vesselTruth.latitude == calm.state.vesselTruth.latitude)
        #expect(drifting.state.vesselTruth.longitude == calm.state.vesselTruth.longitude)
        #expect(drifting.state.vesselTruth.speedOverGroundKnots == calm.state.vesselTruth.speedOverGroundKnots)
        #expect(drifting.state.vesselTruth.courseOverGroundDegrees == calm.state.vesselTruth.courseOverGroundDegrees)
        #expect(drifting.state.vesselTruth.speedThroughWaterKnots == calm.state.vesselTruth.speedThroughWaterKnots)
    }

    @Test
    func anUnpreparedTickKeepsTheExistingEstimatedSpeed() {
        var runtime = experimentBaseline()
        runtime.state.twd.centerValue = 180
        runtime.state.twd.offset = 0
        runtime.state.twd.value = 180
        runtime.state.tws.centerValue = 12
        runtime.state.tws.offset = 0
        runtime.state.tws.value = 12
        #expect(runtime.state.hiddenPolarOverride == nil)
        #expect(runtime.state.experimentRandomGenerator == nil)

        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_010_000))

        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs((runtime.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar) < 0.000_001)
        #expect(runtime.state.hiddenPolarOverride == nil)
        #expect(runtime.state.experimentRandomGenerator == nil)
        #expect(runtime.config.boatProfile == .beneteauFirst407)
    }

    @Test
    func aLaterScenarioDoesNotInheritThePreviousRun() {
        let baseline = experimentBaseline()
        let baselineWind = baseline.state.twd.value
        var earlier = ExperimentScenarioRunner.prepare(
            experimentScenario(seed: 1, direction: 180, speed: 12),
            from: baseline
        )
        tick(&earlier, at: Date(timeIntervalSince1970: 1_800_010_000))
        earlier.state.heading.offset = 25

        let nextScenario = experimentScenario(seed: 2, direction: 45, speed: 8)
        let fromCleanBaseline = ExperimentScenarioRunner.prepare(nextScenario, from: baseline)
        let fromUsedRun = ExperimentScenarioRunner.prepare(nextScenario, from: earlier)

        #expect(baseline.state.twd.value == baselineWind)
        #expect(fromCleanBaseline.state.environmentTruth.trueWindDirection == 45)
        #expect(fromCleanBaseline.state.environmentTruth.trueWindSpeedKnots == 8)
        #expect(fromCleanBaseline.state.hiddenPolarOverride == .beneteauFirst407)
        #expect(fromUsedRun.state.environmentTruth.trueWindDirection == 45)
        #expect(fromUsedRun.state.environmentTruth.trueWindSpeedKnots == 8)
        #expect(fromUsedRun.state.twd.offset == 0)
        #expect(fromUsedRun.state.heading.offset == 25)

        var repeated = ExperimentScenarioRunner.prepare(nextScenario, from: experimentBaseline())
        var reused = fromCleanBaseline
        let start = Date(timeIntervalSince1970: 1_800_010_100)
        tick(&repeated, at: start)
        tick(&reused, at: start)
        #expect(repeated.state.vesselTruth == reused.state.vesselTruth)
        #expect(repeated.state.environmentTruth == reused.state.environmentTruth)
    }
}

private final class ExperimentMemoryStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    func loadDocument() throws -> VesselProfileDocument? { document }
    func saveDocument(_ document: VesselProfileDocument) throws { self.document = document }
}

private func experimentBaseline() -> ExperimentRuntime {
    let suite = "ExperimentRunner.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults, vesselStore: ExperimentMemoryStore())
    simulator.outputEndpoints[0].isEnabled = false
    simulator.weatherSourceMode = .manual
    simulator.boatSpeedMode = .estimated
    simulator.boatProfile = .beneteauFirst407
    simulator.mwvReferenceMode = .trueReference
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.sensorToggles.hasGPS = true
    let time = Date(timeIntervalSince1970: 1_800_010_000)
    simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.twd = SimulatedValue(type: .windDirection, center: 10, offset: 20, value: 10)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 4, offset: 3, value: 4)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    var state = SimulationState(from: simulator)
    state.vesselTruth.trueHeading = 90
    state.vesselTruth.speedThroughWaterKnots = 6
    return ExperimentRuntime(state: state, config: simulator.captureSimulationConfig())
}

private func experimentScenario(
    seed: UInt64,
    reference: BoatProfile = .beneteauFirst407,
    hidden: BoatProfile = .beneteauFirst407,
    direction: Double = 180,
    speed: Double = 12,
    current: ExperimentCurrentProgram = .none
) -> ExperimentScenario {
    ExperimentScenario(
        name: "Controlled run",
        seed: seed,
        referencePolarProfile: reference,
        hiddenPolarProfile: hidden,
        windProgram: .steady(trueWindDirectionDegrees: direction, speedKnots: speed),
        currentProgram: current,
        durationSeconds: 60,
        sampleIntervalSeconds: 1
    )
}

private func expectSameCourse(_ lhs: VesselTruth, _ rhs: VesselTruth) {
    #expect(lhs.latitude == rhs.latitude)
    #expect(lhs.longitude == rhs.longitude)
    #expect(lhs.trueHeading == rhs.trueHeading)
    #expect(lhs.speedThroughWaterKnots == rhs.speedThroughWaterKnots)
    #expect(lhs.speedOverGroundKnots == rhs.speedOverGroundKnots)
    #expect(lhs.courseOverGroundDegrees == rhs.courseOverGroundDegrees)
}

private func replacingProfile(_ config: SimulationConfig, profile: BoatProfile? = nil, tack: Bool? = nil) -> SimulationConfig {
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

private func tick(_ runtime: inout ExperimentRuntime, at timestamp: Date) {
    _ = SimulationEngine.tickSimulation(
        state: &runtime.state,
        config: runtime.config,
        at: timestamp,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
}

private func publishedText(_ runtime: ExperimentRuntime) -> String {
    let suite = "ExperimentSentence.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults, vesselStore: ExperimentMemoryStore())
    var relative = false
    let snapshot = runtime.state.latestSnapshot
    let sentences = snapshot.map {
        simulator.buildNMEASentences(
            talkerID: "II",
            type: .mwv,
            snapshot: $0,
            sendRelativeWind: &relative,
            config: runtime.config
        )
    } ?? []
    return ([String(reflecting: runtime.state.vesselObservation), String(reflecting: snapshot as Any)] + sentences).joined(separator: "\n")
}
