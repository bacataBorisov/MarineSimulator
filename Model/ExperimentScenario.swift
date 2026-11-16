import Foundation

/// Versioned description of one controlled research run.
///
/// This is deliberately a data contract only. It does not persist itself, modify a running
/// simulator, or export observations. Those operations need separate contracts so a normal
/// operator session cannot accidentally become a research experiment.
struct ExperimentScenario: Codable, Equatable, Sendable, Identifiable {
    static let supportedFormatVersion = 1

    let id: UUID
    var formatVersion: Int
    var name: String
    var seed: UInt64
    /// The polar presented to a future estimator as its starting reference.
    var referencePolarProfile: BoatProfile
    /// The polar used internally to generate vessel truth. It must never be emitted as NMEA.
    var hiddenPolarProfile: BoatProfile
    /// Truth-only performance parameters (hull/sail/trim/sea-state factors and speed lag). Never emitted as NMEA.
    var hiddenPerformance: PerformanceParameters
    var windProgram: ExperimentWindProgram
    var currentProgram: ExperimentCurrentProgram
    /// Optional steady turn rate during an experiment run (degrees/sec) to sweep across TWAs.
    var courseSweepDegreesPerSecond: Double
    /// Declares which observations a future export is permitted to contain.
    var outputContract: ExperimentOutputContract
    var durationSeconds: TimeInterval
    var sampleIntervalSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        formatVersion: Int = ExperimentScenario.supportedFormatVersion,
        name: String,
        seed: UInt64,
        referencePolarProfile: BoatProfile,
        hiddenPolarProfile: BoatProfile,
        hiddenPerformance: PerformanceParameters = PerformanceParameters(),
        windProgram: ExperimentWindProgram,
        currentProgram: ExperimentCurrentProgram = .none,
        courseSweepDegreesPerSecond: Double = 0,
        outputContract: ExperimentOutputContract = .estimatorInput,
        durationSeconds: TimeInterval,
        sampleIntervalSeconds: TimeInterval
    ) {
        self.id = id
        self.formatVersion = formatVersion
        self.name = name
        self.seed = seed
        self.referencePolarProfile = referencePolarProfile
        self.hiddenPolarProfile = hiddenPolarProfile
        self.hiddenPerformance = hiddenPerformance
        self.windProgram = windProgram
        self.currentProgram = currentProgram
        self.courseSweepDegreesPerSecond = courseSweepDegreesPerSecond
        self.outputContract = outputContract
        self.durationSeconds = durationSeconds
        self.sampleIntervalSeconds = sampleIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        name = try c.decode(String.self, forKey: .name)
        seed = try c.decode(UInt64.self, forKey: .seed)
        referencePolarProfile = try c.decode(BoatProfile.self, forKey: .referencePolarProfile)
        hiddenPolarProfile = try c.decode(BoatProfile.self, forKey: .hiddenPolarProfile)
        hiddenPerformance = try c.decodeIfPresent(PerformanceParameters.self, forKey: .hiddenPerformance) ?? PerformanceParameters()
        windProgram = try c.decode(ExperimentWindProgram.self, forKey: .windProgram)
        currentProgram = try c.decodeIfPresent(ExperimentCurrentProgram.self, forKey: .currentProgram) ?? .none
        courseSweepDegreesPerSecond = try c.decodeIfPresent(Double.self, forKey: .courseSweepDegreesPerSecond) ?? 0
        outputContract = try c.decodeIfPresent(ExperimentOutputContract.self, forKey: .outputContract) ?? .estimatorInput
        durationSeconds = try c.decode(TimeInterval.self, forKey: .durationSeconds)
        sampleIntervalSeconds = try c.decode(TimeInterval.self, forKey: .sampleIntervalSeconds)
    }

    /// A stable first experiment: Extasy's reference polar is also the hidden truth.
    /// Later scenarios may deliberately choose a different hidden polar or parameters.
    static let extasyBaseline = ExperimentScenario(
        name: "Extasy baseline",
        seed: 1,
        referencePolarProfile: .beneteauFirst407,
        hiddenPolarProfile: .beneteauFirst407,
        windProgram: .steady(trueWindDirectionDegrees: 90, speedKnots: 12),
        durationSeconds: 1_800,
        sampleIntervalSeconds: 1
    )

    func sanitized() -> ExperimentScenario {
        var copy = self
        copy.formatVersion = Self.supportedFormatVersion
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty { copy.name = "Untitled experiment" }
        copy.hiddenPerformance = copy.hiddenPerformance.sanitized()
        copy.windProgram = copy.windProgram.sanitized()
        copy.currentProgram = copy.currentProgram.sanitized()
        copy.courseSweepDegreesPerSecond = Self.finite(copy.courseSweepDegreesPerSecond, fallback: 0, range: -30...30)
        copy.outputContract = copy.outputContract.sanitized()
        copy.durationSeconds = Self.finite(copy.durationSeconds, fallback: 1_800, range: 1...86_400)
        copy.sampleIntervalSeconds = Self.finite(
            copy.sampleIntervalSeconds,
            fallback: 1,
            range: 0.05...copy.durationSeconds
        )
        return copy
    }

    private static func finite(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return value.clamped(to: range)
    }
}

/// Wind program v1 with optional smooth sinusoidal shift and speed oscillation.
struct ExperimentWindProgram: Codable, Equatable, Sendable {
    var trueWindDirectionDegrees: Double
    var speedKnots: Double
    var directionSwingDegrees: Double
    var speedAmplitudeKnots: Double
    var periodSeconds: TimeInterval

    init(
        trueWindDirectionDegrees: Double,
        speedKnots: Double,
        directionSwingDegrees: Double = 0,
        speedAmplitudeKnots: Double = 0,
        periodSeconds: TimeInterval = 120
    ) {
        self.trueWindDirectionDegrees = trueWindDirectionDegrees
        self.speedKnots = speedKnots
        self.directionSwingDegrees = directionSwingDegrees
        self.speedAmplitudeKnots = speedAmplitudeKnots
        self.periodSeconds = periodSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trueWindDirectionDegrees = try c.decode(Double.self, forKey: .trueWindDirectionDegrees)
        speedKnots = try c.decode(Double.self, forKey: .speedKnots)
        directionSwingDegrees = try c.decodeIfPresent(Double.self, forKey: .directionSwingDegrees) ?? 0
        speedAmplitudeKnots = try c.decodeIfPresent(Double.self, forKey: .speedAmplitudeKnots) ?? 0
        periodSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .periodSeconds) ?? 120
    }

    static func steady(trueWindDirectionDegrees: Double, speedKnots: Double) -> ExperimentWindProgram {
        ExperimentWindProgram(
            trueWindDirectionDegrees: trueWindDirectionDegrees,
            speedKnots: speedKnots
        )
    }

    func sample(elapsedSeconds: TimeInterval) -> (directionDegrees: Double, speedKnots: Double) {
        let clean = sanitized()
        guard clean.directionSwingDegrees > 0 || clean.speedAmplitudeKnots > 0,
              elapsedSeconds.isFinite,
              clean.periodSeconds > 0 else {
            return (clean.trueWindDirectionDegrees, clean.speedKnots)
        }
        let phase = 2 * Double.pi * max(0, elapsedSeconds) / clean.periodSeconds
        let wave = sin(phase)
        let direction = Self.normalizedAngle(clean.trueWindDirectionDegrees + clean.directionSwingDegrees * wave)
        let speed = max(0, clean.speedKnots + clean.speedAmplitudeKnots * wave)
        return (direction, speed)
    }

    func sanitized() -> ExperimentWindProgram {
        ExperimentWindProgram(
            trueWindDirectionDegrees: Self.normalizedAngle(trueWindDirectionDegrees),
            speedKnots: Self.nonNegativeFinite(speedKnots),
            directionSwingDegrees: directionSwingDegrees.isFinite ? min(max(directionSwingDegrees, 0), 180) : 0,
            speedAmplitudeKnots: speedAmplitudeKnots.isFinite ? min(max(speedAmplitudeKnots, 0), 40) : 0,
            periodSeconds: periodSeconds.isFinite ? min(max(periodSeconds, 5), 3_600) : 120
        )
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let normalized = value.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    private static func nonNegativeFinite(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

/// Set-and-drift current declaration. This is intentionally inert until the vessel-motion
/// model gets an explicitly approved current implementation.
struct ExperimentCurrentProgram: Codable, Equatable, Sendable {
    var setDegrees: Double
    var driftKnots: Double

    static let none = ExperimentCurrentProgram(setDegrees: 0, driftKnots: 0)

    func sanitized() -> ExperimentCurrentProgram {
        ExperimentCurrentProgram(
            setDegrees: ExperimentWindProgram.steady(
                trueWindDirectionDegrees: setDegrees,
                speedKnots: 0
            ).sanitized().trueWindDirectionDegrees,
            driftKnots: driftKnots.isFinite ? max(0, driftKnots) : 0
        )
    }
}

/// Explicit boundary between measurements that a future estimator may receive and simulator
/// truth used only for internal validation.
struct ExperimentOutputContract: Codable, Equatable, Sendable {
    var measurementFields: [ExperimentMeasurementField]
    var permitsGroundTruthExport: Bool

    static let estimatorInput = ExperimentOutputContract(
        measurementFields: [.timestamp, .trueWindDirection, .trueWindSpeed, .trueHeading, .speedThroughWater],
        permitsGroundTruthExport: false
    )

    func sanitized() -> ExperimentOutputContract {
        var seen = Set<ExperimentMeasurementField>()
        return ExperimentOutputContract(
            measurementFields: measurementFields.filter { seen.insert($0).inserted },
            permitsGroundTruthExport: permitsGroundTruthExport
        )
    }
}

enum ExperimentMeasurementField: String, Codable, CaseIterable, Sendable {
    case timestamp
    case trueWindDirection
    case trueWindSpeed
    case trueHeading
    case speedThroughWater
    case speedOverGround
    case courseOverGround
    case latitude
    case longitude
}
