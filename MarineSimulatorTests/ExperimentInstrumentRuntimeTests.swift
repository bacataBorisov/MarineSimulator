import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct ExperimentInstrumentRuntimeTests {

    @Test
    func zeroErrorPublishesCalculatedWindAndRepeatsTheSameSentences() {
        let start = Date(timeIntervalSince1970: 1_800_020_000)
        var first = prepared(seed: 4)
        var second = prepared(seed: 4)
        tick(&first, at: start)
        tick(&second, at: start)

        let publication = first.state.latestSnapshot?.experimentPublication
        expectAngle(publication?.trueWindAngleDegrees, 90)
        expectClose(publication?.trueWindSpeedKnots, 12)
        expectAngle(publication?.trueWindDirectionDegrees, 180)
        expectAngle(publication?.trueHeadingDegrees, first.state.vesselTruth.trueHeading)
        #expect(first.state.vesselTruth == second.state.vesselTruth)
        #expect(sentences(first, .mwv) == sentences(second, .mwv))
        #expect(sentences(first, .hdg) == sentences(second, .hdg))
        #expect(sentences(first, .hdt) == sentences(second, .hdt))
        #expect(fields(sentences(first, .mwv)[0])[2] == "T")
        #expect(fields(sentences(first, .mwv)[0])[3] == "12.0")
    }

    @Test
    func apparentWindBiasChangesOnlyTheRelativeSentence() {
        var runtime = prepared(seed: 6)
        runtime.state.experimentInstruments?.errors.apparentWindSpeed.bias = 1.5
        runtime.config = replacing(runtime.config, windMode: .relative)
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_020_100))
        let truth = runtime.state.vesselTruth
        let ideal = ExperimentSensorModel.apparentWind(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: ExperimentSensorModel.trueWindAngleDegrees(
                trueHeading: truth.trueHeading,
                trueWindDirection: 180
            ),
            speedThroughWaterKnots: truth.speedThroughWaterKnots ?? 0
        )
        let relative = fields(sentences(runtime, .mwv)[0])
        #expect(relative[2] == "R")
        expectClose(runtime.state.latestSnapshot?.experimentPublication?.apparentWindSpeedKnots, ideal.speedKnots + 1.5)
        #expect(relative[3] == NMEANumericFormatting.format(ideal.speedKnots + 1.5, fractionDigits: 1))
        #expect(runtime.state.environmentTruth.trueWindSpeedKnots == 12)

        var angleRun = prepared(seed: 6)
        angleRun.state.experimentInstruments?.errors.apparentWindAngle.bias = -20
        angleRun.config = replacing(angleRun.config, windMode: .relative)
        tick(&angleRun, at: Date(timeIntervalSince1970: 1_800_020_100))
        let shifted = fields(sentences(angleRun, .mwv)[0])
        let shiftedAngle = normalizeAngle(ideal.angleDegrees - 20)
        expectAngle(angleRun.state.latestSnapshot?.experimentPublication?.apparentWindAngleDegrees, shiftedAngle)
        #expect(shifted[1] == NMEANumericFormatting.format(shiftedAngle, fractionDigits: 0))
        #expect(angleRun.state.vesselTruth.trueHeading == truth.trueHeading)
    }

    @Test
    func speedLogBiasChangesVHWAndCalculatedTrueWind() {
        var runtime = prepared(seed: 8)
        runtime.state.experimentInstruments?.errors.speedThroughWater.bias = 0.5
        let time = Date(timeIntervalSince1970: 1_800_020_200)
        tick(&runtime, at: time)
        let physical = runtime.state.vesselTruth.speedThroughWaterKnots ?? -1
        let publication = runtime.state.latestSnapshot?.experimentPublication
        expectClose(publication?.speedThroughWaterKnots, physical + 0.5)
        #expect(publication?.trueWindSpeedKnots != 12)
        let vhw = fields(sentences(runtime, .vhw)[0])
        #expect(vhw[5] == NMEANumericFormatting.format(physical + 0.5, fractionDigits: 1))
        #expect(runtime.state.vesselTruth.speedThroughWaterKnots == physical)
    }

    @Test
    func trueHeadingBiasChangesDirectionAndNotTheCompassSentence() {
        var plain = prepared(seed: 9)
        var biased = prepared(seed: 9)
        biased.state.experimentInstruments?.errors.trueHeading.bias = 15
        let time = Date(timeIntervalSince1970: 1_800_020_300)
        tick(&plain, at: time)
        tick(&biased, at: time)
        let calm = plain.state.latestSnapshot?.experimentPublication
        let shifted = biased.state.latestSnapshot?.experimentPublication
        expectAngle(shifted?.trueHeadingDegrees, normalizeAngle((calm?.trueHeadingDegrees ?? 0) + 15))
        expectAngle(shifted?.trueWindDirectionDegrees, normalizeAngle((calm?.trueWindDirectionDegrees ?? 0) + 15))
        #expect(shifted?.trueWindSpeedKnots == calm?.trueWindSpeedKnots)
        #expect(shifted?.trueWindAngleDegrees == calm?.trueWindAngleDegrees)
        #expect(sentences(plain, .hdg) == sentences(biased, .hdg))
        #expect(plain.state.vesselTruth == biased.state.vesselTruth)
    }

    @Test
    func compassBiasDoesNotChangeTheGyroOrTrueWindDirection() {
        var plain = prepared(seed: 10)
        var biased = prepared(seed: 10)
        biased.state.experimentInstruments?.errors.magneticCompass.bias = 12
        let time = Date(timeIntervalSince1970: 1_800_020_400)
        tick(&plain, at: time)
        tick(&biased, at: time)
        let calm = plain.state.latestSnapshot?.experimentPublication
        let shifted = biased.state.latestSnapshot?.experimentPublication
        expectAngle(shifted?.magneticCompassHeadingDegrees, normalizeAngle((calm?.magneticCompassHeadingDegrees ?? 0) + 12))
        #expect(shifted?.trueHeadingDegrees == calm?.trueHeadingDegrees)
        #expect(shifted?.trueWindDirectionDegrees == calm?.trueWindDirectionDegrees)
        #expect(sentences(plain, .hdt) == sentences(biased, .hdt))
        #expect(fields(sentences(biased, .hdg)[0])[1] != fields(sentences(plain, .hdg)[0])[1])
    }

    @Test
    func gyroDisabledUsesTheCorrectedCompassAndDoesNotCopyPhysicalHeading() {
        var runtime = prepared(seed: 11)
        var gyroOff = runtime.config.sensorToggles
        gyroOff.hasGyro = false
        runtime.config = replacing(runtime.config, toggles: gyroOff)
        runtime.state.experimentInstruments?.errors.magneticCompass.bias = 10
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_020_500))
        let publication = runtime.state.latestSnapshot?.experimentPublication
        #expect(publication?.trueHeadingDegrees == nil)
        #expect(sentences(runtime, .hdt).isEmpty)
        #expect(sentences(runtime, .hdg).isEmpty == false)
        expectAngle(publication?.resolvedTrueHeadingDegrees, normalizeAngle(runtime.state.vesselTruth.trueHeading + 10))
        expectAngle(publication?.trueWindDirectionDegrees, normalizeAngle(180 + 10))
        #expect(publication?.resolvedTrueHeadingDegrees != runtime.state.vesselTruth.trueHeading)
        #expect(runtime.state.vesselTruth.trueHeading != 0)
    }

    @Test
    func compassDisabledKeepsTheGyroAndOmitsHDG() {
        var runtime = prepared(seed: 12)
        var compassOff = runtime.config.sensorToggles
        compassOff.hasCompass = false
        runtime.config = replacing(runtime.config, toggles: compassOff)
        runtime.state.experimentInstruments?.errors.trueHeading.bias = -20
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_020_600))
        let publication = runtime.state.latestSnapshot?.experimentPublication
        #expect(publication?.magneticCompassHeadingDegrees == nil)
        #expect(sentences(runtime, .hdg).isEmpty)
        expectAngle(publication?.trueHeadingDegrees, normalizeAngle(runtime.state.vesselTruth.trueHeading - 20))
        expectAngle(publication?.trueWindDirectionDegrees, normalizeAngle(180 - 20))
        #expect(sentences(runtime, .hdt).isEmpty == false)
        #expect(runtime.state.vesselTruth.magneticHeading != nil)
    }

    @Test
    func bothHeadingInstrumentsLeaveTrueWindDirectionUnpublished() {
        var runtime = prepared(seed: 13)
        var headingsOff = runtime.config.sensorToggles
        headingsOff.hasGyro = false
        headingsOff.hasCompass = false
        runtime.config = replacing(runtime.config, toggles: headingsOff)
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_020_700))
        let publication = runtime.state.latestSnapshot?.experimentPublication
        #expect(publication?.trueHeadingDegrees == nil)
        #expect(publication?.magneticCompassHeadingDegrees == nil)
        #expect(publication?.trueWindDirectionDegrees == nil)
        expectClose(publication?.trueWindSpeedKnots, 12)
        #expect(sentences(runtime, .hdt).isEmpty)
        #expect(sentences(runtime, .hdg).isEmpty)
        #expect(sentences(runtime, .mwd).isEmpty)
        #expect(fields(sentences(runtime, .mwv)[0])[2] == "T")
        #expect(runtime.state.vesselTruth.trueHeading != 0)
    }

    @Test
    func disabledWindAndLogOmitTheirSentencesWithoutStoppingTheBoat() {
        let time = Date(timeIntervalSince1970: 1_800_020_800)
        var windOff = prepared(seed: 14)
        var windOn = prepared(seed: 14)
        var anemometerOff = windOff.config.sensorToggles
        anemometerOff.hasAnemometer = false
        windOff.config = replacing(windOff.config, toggles: anemometerOff)
        tick(&windOff, at: time)
        tick(&windOn, at: time)
        #expect(windOff.state.environmentTruth.trueWindSpeedKnots == 12)
        #expect(windOff.state.vesselTruth == windOn.state.vesselTruth)
        #expect(windOff.state.latestSnapshot?.experimentPublication?.apparentWindSpeedKnots == nil)
        #expect(sentences(windOff, .mwv).isEmpty)

        var logOff = prepared(seed: 14)
        var speedLogOff = logOff.config.sensorToggles
        speedLogOff.hasSpeedLog = false
        logOff.config = replacing(logOff.config, toggles: speedLogOff, windMode: .relative)
        tick(&logOff, at: Date(timeIntervalSince1970: 1_800_020_800))
        #expect(logOff.state.vesselTruth.speedThroughWaterKnots != nil)
        #expect(logOff.state.latestSnapshot?.boatSpeed == nil)
        #expect(logOff.state.latestSnapshot?.experimentPublication?.speedThroughWaterKnots == nil)
        #expect(logOff.state.latestSnapshot?.experimentPublication?.trueWindSpeedKnots == nil)
        #expect(logOff.state.latestSnapshot?.experimentPublication?.apparentWindSpeedKnots != nil)
        #expect(fields(sentences(logOff, .vhw)[0])[5].isEmpty)
        #expect(fields(sentences(logOff, .mwv)[0])[2] == "R")
    }

    @Test
    func negativeSpeedIsOmittedAndHeadingWraps() {
        var negative = prepared(seed: 15)
        negative.state.experimentInstruments?.errors.speedThroughWater.bias = -100
        tick(&negative, at: Date(timeIntervalSince1970: 1_800_020_900))
        #expect(negative.state.latestSnapshot?.experimentPublication?.speedThroughWaterKnots == nil)
        #expect(negative.state.latestSnapshot?.experimentPublication?.trueWindSpeedKnots == nil)
        #expect(fields(sentences(negative, .vhw)[0])[5].isEmpty)
        #expect(negative.state.vesselTruth.speedThroughWaterKnots ?? 0 > 0)

        var wrapped = prepared(seed: 16)
        let variation = SimulationEngine.simulatedMagneticVariation(
            for: wrapped.state.gpsData,
            at: Date(timeIntervalSince1970: 1_800_021_000)
        )
        let magnetic = normalizeAngle(350 - variation)
        wrapped.state.heading.centerValue = magnetic
        wrapped.state.heading.offset = 0
        wrapped.state.heading.value = magnetic
        wrapped.state.vesselTruth.trueHeading = 350
        wrapped.state.vesselTruth.magneticHeading = magnetic
        wrapped.state.twd.centerValue = 10
        wrapped.state.twd.offset = 0
        wrapped.state.twd.value = 10
        wrapped.state.environmentTruth.trueWindDirection = 10
        wrapped.state.experimentInstruments?.errors.trueHeading.bias = 20
        tick(&wrapped, at: Date(timeIntervalSince1970: 1_800_021_000))
        let publication = wrapped.state.latestSnapshot?.experimentPublication
        expectAngle(publication?.trueHeadingDegrees, 10)
        expectAngle(publication?.trueWindAngleDegrees, 20)
        expectAngle(publication?.trueWindDirectionDegrees, 30)
    }

    @Test
    func publicationDoesNotDrawAgainAndARestartBeginsAtTheFirstSample() {
        var runtime = prepared(seed: 18)
        runtime.state.experimentInstruments?.errors.trueHeading.noiseAmplitude = 4
        let start = Date(timeIntervalSince1970: 1_800_021_100)
        tick(&runtime, at: start)
        let firstSentences = sentences(runtime, .hdt) + sentences(runtime, .mwv)
        #expect(sentences(runtime, .hdt) + sentences(runtime, .mwv) == firstSentences)
        var twin = prepared(seed: 18)
        twin.state.experimentInstruments?.errors.trueHeading.noiseAmplitude = 4
        tick(&twin, at: start)
        _ = sentences(runtime, .hdg)
        tick(&runtime, at: start.addingTimeInterval(1))
        tick(&twin, at: start.addingTimeInterval(1))
        #expect(sentences(runtime, .hdt) == sentences(twin, .hdt))
        #expect(runtime.state.vesselTruth == twin.state.vesselTruth)

        var restarted = ExperimentScenarioRunner.prepare(experiment(seed: 18), from: baseline())
        restarted.state.experimentInstruments?.errors.trueHeading.noiseAmplitude = 4
        tick(&restarted, at: start)
        var fresh = prepared(seed: 18)
        fresh.state.experimentInstruments?.errors.trueHeading.noiseAmplitude = 4
        tick(&fresh, at: start)
        #expect(sentences(restarted, .hdt) == sentences(fresh, .hdt))
    }

    @Test
    func measurementBiasDoesNotMoveTheBoatOrRevealTheHiddenPolar() {
        let start = Date(timeIntervalSince1970: 1_800_021_200)
        var calm = prepared(seed: 21, hidden: .nimana)
        var noisy = prepared(seed: 21, hidden: .nimana)
        noisy.state.experimentInstruments?.errors.apparentWindSpeed.bias = 3
        noisy.state.experimentInstruments?.errors.trueHeading.bias = 25
        noisy.state.experimentInstruments?.errors.speedThroughWater.bias = 1
        for step in 0...2 {
            let time = start.addingTimeInterval(TimeInterval(step))
            tick(&calm, at: time)
            tick(&noisy, at: time)
        }
        #expect(calm.state.vesselTruth == noisy.state.vesselTruth)
        #expect(calm.state.environmentTruth == noisy.state.environmentTruth)
        #expect(calm.state.hiddenPolarOverride == .nimana)
        let published = sentences(noisy, .mwv).joined()
        #expect(published.contains("nimana") == false)
        #expect(published.contains("hidden") == false)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? 0
        #expect(abs((calm.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar) > 0.5)
    }

    @Test
    func aNormalSessionKeepsTheExistingHeadingSentence() {
        var experiment = prepared(seed: 22)
        var normal = experiment
        normal.state.experimentInstruments = nil
        let time = Date(timeIntervalSince1970: 1_800_021_300)
        tick(&experiment, at: time)
        tick(&normal, at: time)
        #expect(normal.state.latestSnapshot?.experimentPublication == nil)
        #expect(experiment.state.vesselTruth == normal.state.vesselTruth)
        let magnetic = normal.state.latestSnapshot?.magneticHeading ?? -1
        let normalHeading = fields(sentences(normal, .hdg)[0])[1]
        #expect(normalHeading == NMEANumericFormatting.format(magnetic, fractionDigits: 1))
        let card = experiment.state.latestSnapshot?.experimentPublication?.magneticCompassHeadingDegrees ?? magnetic
        let deviation = experiment.state.latestSnapshot?.experimentPublication?.compassDeviationDegrees ?? 0
        #expect(abs(normalizeAngleTo180(card - magnetic) + deviation) <= 1e-6)
        #expect(fields(sentences(experiment, .hdg)[0])[1] == NMEANumericFormatting.format(card, fractionDigits: 1))
        #expect(fields(sentences(normal, .mwv)[0])[3] == "12.0")
    }

    @Test
    func wireFaultsStayAfterTheSentenceAndDoNotChangeTruth() {
        var runtime = prepared(seed: 23)
        tick(&runtime, at: Date(timeIntervalSince1970: 1_800_021_400))
        let before = runtime.state.vesselTruth
        let sentence = sentences(runtime, .mwv)[0]
        let corrupted = SentenceScheduler.corruptedChecksumSentence(from: sentence)
        #expect(corrupted != nil)
        #expect(corrupted != sentence)
        #expect(runtime.state.vesselTruth == before)
        var settings = FaultInjectionSettings()
        settings.dropRate = 0
        let untouched = SentenceScheduler.applyFaultInjection(
            to: [sentence],
            for: .mwv,
            at: Date(timeIntervalSince1970: 1_800_021_400),
            faultInjection: settings,
            interval: 1
        )
        #expect(untouched.transmitted == [sentence])
        #expect(runtime.state.vesselTruth == before)
    }
}

private func prepared(seed: UInt64, hidden: BoatProfile = .beneteauFirst407) -> ExperimentRuntime {
    ExperimentScenarioRunner.prepare(experiment(seed: seed, hidden: hidden), from: baseline())
}

private func experiment(seed: UInt64, hidden: BoatProfile = .beneteauFirst407) -> ExperimentScenario {
    ExperimentScenario(
        name: "Instrument runtime",
        seed: seed,
        referencePolarProfile: .beneteauFirst407,
        hiddenPolarProfile: hidden,
        windProgram: .steady(trueWindDirectionDegrees: 180, speedKnots: 12),
        durationSeconds: 60,
        sampleIntervalSeconds: 1
    )
}

private func baseline() -> ExperimentRuntime {
    let suite = "ExperimentInstruments.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
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
    let time = Date(timeIntervalSince1970: 1_800_020_000)
    simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    var state = SimulationState(from: simulator)
    state.vesselTruth.trueHeading = 90
    state.vesselTruth.speedThroughWaterKnots = 6
    return ExperimentRuntime(state: state, config: simulator.captureSimulationConfig())
}

private func replacing(
    _ config: SimulationConfig,
    toggles: SensorToggleStates? = nil,
    windMode: MWVReferenceMode? = nil
) -> SimulationConfig {
    SimulationConfig(
        sensorToggles: toggles ?? config.sensorToggles,
        sentenceToggles: config.sentenceToggles,
        interval: config.interval,
        sentenceIntervals: config.sentenceIntervals,
        weatherSourceMode: config.weatherSourceMode,
        latestLiveWeather: config.latestLiveWeather,
        boatSpeedMode: config.boatSpeedMode,
        boatProfile: config.boatProfile,
        waypointNavigation: config.waypointNavigation,
        tackAnimationInProgress: config.tackAnimationInProgress,
        maneuverSettings: config.maneuverSettings,
        talkerID: config.talkerID,
        perSentenceTalkerID: config.perSentenceTalkerID,
        depthOffsetMeters: config.depthOffsetMeters,
        faultInjection: config.faultInjection,
        mwvReferenceMode: windMode ?? config.mwvReferenceMode,
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

private func sentences(_ runtime: ExperimentRuntime, _ type: NMEASentenceType) -> [String] {
    let suite = "ExperimentSentence.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    var relative = false
    guard let snapshot = runtime.state.latestSnapshot else { return [] }
    return simulator.buildNMEASentences(
        talkerID: "II",
        type: type,
        snapshot: snapshot,
        sendRelativeWind: &relative,
        config: runtime.config
    )
}

private func fields(_ sentence: String) -> [String] {
    let body = sentence.split(separator: "*").first.map(String.init) ?? sentence
    return body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
}

private func expectClose(_ value: Double?, _ expected: Double) {
    #expect(abs((value ?? .nan) - expected) <= 1e-9)
}

private func expectAngle(_ value: Double?, _ expected: Double) {
    #expect(abs(normalizeAngleTo180((value ?? .nan) - expected)) <= 1e-6)
}
