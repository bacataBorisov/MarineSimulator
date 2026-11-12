import Foundation
import Observation

/// Isolated experimental run for the diagnostics window.
///
/// Preparing a session copies a clean baseline and calls `ExperimentScenarioRunner`.
/// It does not read or write the operator `NMEASimulator`, `UserDefaults.standard`, or the vessel file.
/// The wall-clock loop is off until the diagnostics view enables it, so tests step the clock directly.
@MainActor
@Observable
final class ExperimentDiagnosticsSession {
    enum Phase: Equatable {
        case idle
        case prepared
        case running
        case paused
        case complete
    }

    enum Channel: Equatable {
        case apparentWindSpeed
        case apparentWindAngle
        case speedThroughWater
        case trueHeading
        case magneticCompass
    }

    static let physicsInterval = NMEASimulator.simulationFastTickInterval
    static let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private(set) var phase: Phase = .idle
    private(set) var stepCount = 0
    private(set) var validationMessage: String?
    private(set) var runtime: ExperimentRuntime?

    var seed: UInt64 = 1
    var windDirectionDegrees: Double = 90
    var windSpeedKnots: Double = 12
    var durationSeconds: TimeInterval = 1_800
    var errors = SensorErrorConfiguration.zero
    var windInstrument = true
    var speedLog = true
    var trueHeadingInstrument = true
    var magneticCompass = true
    var allowsWallClockLoop = false

    private var appliedErrors = SensorErrorConfiguration.zero
    private var appliedScenario = ExperimentScenario.extasyBaseline
    private var loop: Task<Void, Never>?
    private var loopGeneration = 0
    @ObservationIgnored private var sentenceFormatter: NMEASimulator?

    var elapsedSeconds: TimeInterval {
        Double(stepCount) * Self.physicsInterval
    }

    var configurationChangesArePending: Bool {
        guard phase != .idle else { return false }
        let wind = appliedScenario.windProgram
        return errors != appliedErrors
            || seed != appliedScenario.seed
            || windDirectionDegrees != wind.trueWindDirectionDegrees
            || windSpeedKnots != wind.speedKnots
            || durationSeconds != appliedScenario.durationSeconds
    }

    var readout: ExperimentDiagnosticsReadout {
        ExperimentDiagnosticsReadout(
            phase: phase,
            elapsedSeconds: elapsedSeconds,
            durationSeconds: durationSeconds,
            truth: runtime?.state,
            publication: runtime?.state.latestSnapshot?.experimentPublication,
            windInstrument: windInstrument,
            speedLog: speedLog,
            trueHeadingInstrument: trueHeadingInstrument,
            magneticCompass: magneticCompass,
            sentences: currentSentences()
        )
    }

    func rejectUnreadableNumber() {
        validationMessage = "Enter a finite number."
    }

    func setSeed(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = UInt64(trimmed) else {
            validationMessage = "Seed must be a whole number from 0 upward."
            return false
        }
        seed = value
        validationMessage = nil
        return true
    }

    func setWindDirection(_ value: Double) -> Bool {
        guard value.isFinite else {
            validationMessage = "Wind direction must be a finite number of degrees."
            return false
        }
        windDirectionDegrees = normalizeAngle(value)
        validationMessage = nil
        return true
    }

    func setWindSpeed(_ value: Double) -> Bool {
        guard value.isFinite, value >= 0 else {
            validationMessage = "Wind speed must be zero or a positive number of knots."
            return false
        }
        windSpeedKnots = value
        validationMessage = nil
        return true
    }

    func setDuration(_ value: Double) -> Bool {
        guard value.isFinite, (1...86_400).contains(value) else {
            validationMessage = "Duration must be between 1 and 86400 seconds."
            return false
        }
        durationSeconds = value
        validationMessage = nil
        return true
    }

    func setBias(_ value: Double, for channel: Channel) -> Bool {
        guard value.isFinite else {
            validationMessage = "Bias must be a finite number."
            return false
        }
        update(channel) { $0.bias = value }
        validationMessage = nil
        return true
    }

    func setNoiseAmplitude(_ value: Double, for channel: Channel) -> Bool {
        guard value.isFinite, value >= 0 else {
            validationMessage = "Noise amplitude must be zero or positive."
            return false
        }
        update(channel) { $0.noiseAmplitude = value }
        validationMessage = nil
        return true
    }

    func prepare() {
        stopLoop()
        let scenario = makeScenario()
        var prepared = ExperimentScenarioRunner.prepare(scenario, from: Self.cleanBaseline())
        prepared.state.lastSimulationTickDate = Self.origin
        prepared.state.lastSensorEvolutionDate = Self.origin
        prepared.state.experimentInstruments?.errors = errors
        prepared.config = configured(prepared.config)
        runtime = prepared
        appliedErrors = errors
        appliedScenario = scenario
        stepCount = 0
        phase = .prepared
        validationMessage = nil
    }

    func start() {
        guard phase == .prepared || phase == .paused else { return }
        phase = .running
        advance()
        startLoopIfNeeded()
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        stopLoop()
    }

    func resume() {
        start()
    }

    func reset() {
        guard phase != .idle else { return }
        prepare()
    }

    func pauseIfRunning() {
        if phase == .running {
            pause()
        }
    }

    /// One physics step. Ignored unless the session is running, so a paused session stays still.
    func advance() {
        guard phase == .running, var current = runtime else { return }
        let nextElapsed = Double(stepCount + 1) * Self.physicsInterval
        if nextElapsed > durationSeconds + 1e-6 {
            phase = .complete
            stopLoop()
            return
        }
        let timestamp = Self.origin.addingTimeInterval(nextElapsed)
        current.config = configured(current.config)
        _ = SimulationEngine.tickSimulation(
            state: &current.state,
            config: current.config,
            at: timestamp,
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        runtime = current
        stepCount += 1
        if Double(stepCount) * Self.physicsInterval + Self.physicsInterval > durationSeconds + 1e-6 {
            phase = .complete
            stopLoop()
        }
    }

    private func makeScenario() -> ExperimentScenario {
        ExperimentScenario(
            name: "Diagnostics",
            seed: seed,
            referencePolarProfile: .beneteauFirst407,
            hiddenPolarProfile: .beneteauFirst407,
            windProgram: .steady(trueWindDirectionDegrees: windDirectionDegrees, speedKnots: windSpeedKnots),
            durationSeconds: durationSeconds,
            sampleIntervalSeconds: 1
        ).sanitized()
    }

    private func configured(_ config: SimulationConfig) -> SimulationConfig {
        var toggles = config.sensorToggles
        toggles.hasAnemometer = windInstrument
        toggles.hasSpeedLog = speedLog
        toggles.hasGyro = trueHeadingInstrument
        toggles.hasCompass = magneticCompass
        return config.replacing(sensorToggles: toggles)
    }

    private func update(_ channel: Channel, _ change: (inout SensorChannelError) -> Void) {
        switch channel {
        case .apparentWindSpeed: change(&errors.apparentWindSpeed)
        case .apparentWindAngle: change(&errors.apparentWindAngle)
        case .speedThroughWater: change(&errors.speedThroughWater)
        case .trueHeading: change(&errors.trueHeading)
        case .magneticCompass: change(&errors.magneticCompass)
        }
    }

    private func currentSentences() -> [ExperimentDiagnosticSentence] {
        let names = ["MWV relative", "MWV true", "MWD", "VHW", "HDG", "HDT"]
        guard let snapshot = runtime?.state.latestSnapshot, let config = runtime?.config else {
            return names.map { ExperimentDiagnosticSentence(name: $0, text: nil) }
        }
        let builder = makeSentenceBuilder()
        func line(_ type: NMEASentenceType, mode: MWVReferenceMode) -> String? {
            var relative = false
            return builder.buildNMEASentences(
                talkerID: "II",
                type: type,
                snapshot: snapshot,
                sendRelativeWind: &relative,
                config: config.replacing(mwvReferenceMode: mode)
            ).first
        }
        return [
            ExperimentDiagnosticSentence(name: "MWV relative", text: line(.mwv, mode: .relative)),
            ExperimentDiagnosticSentence(name: "MWV true", text: line(.mwv, mode: .trueReference)),
            ExperimentDiagnosticSentence(name: "MWD", text: line(.mwd, mode: .trueReference)),
            ExperimentDiagnosticSentence(name: "VHW", text: line(.vhw, mode: .trueReference)),
            ExperimentDiagnosticSentence(name: "HDG", text: line(.hdg, mode: .trueReference)),
            ExperimentDiagnosticSentence(name: "HDT", text: line(.hdt, mode: .trueReference))
        ]
    }

    private func makeSentenceBuilder() -> NMEASimulator {
        if let sentenceFormatter { return sentenceFormatter }
        let suite = "ExperimentDiagnostics.sentences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults)
        simulator.outputEndpoints[0].isEnabled = false
        sentenceFormatter = simulator
        return simulator
    }

    private func startLoopIfNeeded() {
        guard allowsWallClockLoop, phase == .running, loop == nil else { return }
        loopGeneration += 1
        let generation = loopGeneration
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, !Task.isCancelled, self.loopGeneration == generation, self.phase == .running else { break }
                self.advance()
            }
            if let self, self.loopGeneration == generation {
                self.loop = nil
            }
        }
    }

    private func stopLoop() {
        loopGeneration += 1
        loop?.cancel()
        loop = nil
    }

    private static func cleanBaseline() -> ExperimentRuntime {
        let suite = "ExperimentDiagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults)
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .manual
        simulator.boatSpeedMode = .estimated
        simulator.boatProfile = .beneteauFirst407
        simulator.sensorToggles.hasGyro = true
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasAnemometer = true
        simulator.sensorToggles.hasSpeedLog = true
        simulator.sensorToggles.hasGPS = true
        simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
        let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: origin)
        let magnetic = normalizeAngle(90 - variation)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
        simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0, value: 90)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
        var state = SimulationState(from: simulator)
        state.vesselTruth.trueHeading = 90
        state.vesselTruth.speedThroughWaterKnots = 6
        return ExperimentRuntime(state: state, config: simulator.captureSimulationConfig())
    }
}

/// Display values for the diagnostics window. It has no hidden-polar field.
struct ExperimentDiagnosticsReadout: Equatable {
    var phase: ExperimentDiagnosticsSession.Phase
    var elapsedSeconds: TimeInterval
    var durationSeconds: TimeInterval
    var trueWindSpeedKnots: Double?
    var trueWindDirectionDegrees: Double?
    var trueHeadingDegrees: Double?
    var speedThroughWaterKnots: Double?
    var speedOverGroundKnots: Double?
    var courseOverGroundDegrees: Double?
    var latitude: Double?
    var longitude: Double?
    var idealApparentWindSpeedKnots: Double?
    var idealApparentWindAngleDegrees: Double?
    var apparentWindSpeedKnots: Double?
    var apparentWindAngleDegrees: Double?
    var measuredSpeedThroughWaterKnots: Double?
    var measuredTrueHeadingDegrees: Double?
    var magneticCompassHeadingDegrees: Double?
    var calculatedTrueWindSpeedKnots: Double?
    var calculatedTrueWindAngleDegrees: Double?
    var calculatedTrueWindDirectionDegrees: Double?
    var windInstrument: Bool
    var speedLog: Bool
    var trueHeadingInstrument: Bool
    var magneticCompass: Bool
    var sentences: [ExperimentDiagnosticSentence]

    init(
        phase: ExperimentDiagnosticsSession.Phase,
        elapsedSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        truth state: SimulationState?,
        publication: ExperimentNavigationPublication?,
        windInstrument: Bool,
        speedLog: Bool,
        trueHeadingInstrument: Bool,
        magneticCompass: Bool,
        sentences: [ExperimentDiagnosticSentence]
    ) {
        self.phase = phase
        self.elapsedSeconds = elapsedSeconds
        self.durationSeconds = durationSeconds
        self.windInstrument = windInstrument
        self.speedLog = speedLog
        self.trueHeadingInstrument = trueHeadingInstrument
        self.magneticCompass = magneticCompass
        self.sentences = sentences
        guard let state else { return }
        let environment = state.environmentTruth
        let vessel = state.vesselTruth
        trueWindSpeedKnots = finite(environment.trueWindSpeedKnots)
        trueWindDirectionDegrees = finite(environment.trueWindDirection)
        trueHeadingDegrees = finite(vessel.trueHeading)
        speedThroughWaterKnots = finite(vessel.speedThroughWaterKnots)
        speedOverGroundKnots = finite(vessel.speedOverGroundKnots)
        courseOverGroundDegrees = finite(vessel.courseOverGroundDegrees)
        latitude = finite(vessel.latitude)
        longitude = finite(vessel.longitude)
        if let windSpeed = trueWindSpeedKnots,
           let windDirection = trueWindDirectionDegrees,
           let heading = trueHeadingDegrees,
           let waterSpeed = speedThroughWaterKnots,
           waterSpeed >= 0 {
            let apparent = ExperimentSensorModel.apparentWind(
                trueWindSpeedKnots: windSpeed,
                trueWindAngleDegrees: ExperimentSensorModel.trueWindAngleDegrees(
                    trueHeading: heading,
                    trueWindDirection: windDirection
                ),
                speedThroughWaterKnots: waterSpeed
            )
            idealApparentWindSpeedKnots = apparent.speedKnots
            idealApparentWindAngleDegrees = apparent.angleDegrees
        }
        apparentWindSpeedKnots = finite(publication?.apparentWindSpeedKnots)
        apparentWindAngleDegrees = finite(publication?.apparentWindAngleDegrees)
        measuredSpeedThroughWaterKnots = finite(publication?.speedThroughWaterKnots)
        measuredTrueHeadingDegrees = finite(publication?.trueHeadingDegrees)
        magneticCompassHeadingDegrees = finite(publication?.magneticCompassHeadingDegrees)
        calculatedTrueWindSpeedKnots = finite(publication?.trueWindSpeedKnots)
        calculatedTrueWindAngleDegrees = finite(publication?.trueWindAngleDegrees)
        calculatedTrueWindDirectionDegrees = finite(publication?.trueWindDirectionDegrees)
    }

    static func signedAngleDelta(from reference: Double, to measured: Double) -> Double {
        normalizeAngleTo180(measured - reference)
    }
}

struct ExperimentDiagnosticSentence: Equatable {
    var name: String
    var text: String?
}

private func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

private extension SimulationConfig {
    func replacing(
        sensorToggles: SensorToggleStates? = nil,
        mwvReferenceMode: MWVReferenceMode? = nil
    ) -> SimulationConfig {
        SimulationConfig(
            sensorToggles: sensorToggles ?? self.sensorToggles,
            sentenceToggles: sentenceToggles,
            interval: interval,
            sentenceIntervals: sentenceIntervals,
            weatherSourceMode: weatherSourceMode,
            latestLiveWeather: latestLiveWeather,
            boatSpeedMode: boatSpeedMode,
            boatProfile: boatProfile,
            waypointNavigation: waypointNavigation,
            tackAnimationInProgress: tackAnimationInProgress,
            maneuverSettings: maneuverSettings,
            talkerID: talkerID,
            perSentenceTalkerID: perSentenceTalkerID,
            depthOffsetMeters: depthOffsetMeters,
            faultInjection: faultInjection,
            mwvReferenceMode: mwvReferenceMode ?? self.mwvReferenceMode,
            enabledOutputEndpoints: enabledOutputEndpoints
        )
    }
}
