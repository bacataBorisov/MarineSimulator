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
    var windProgram: ExperimentWindProgram
    /// Declared now, but it has no effect until a future current-model slice implements it.
    var currentProgram: ExperimentCurrentProgram
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
        windProgram: ExperimentWindProgram,
        currentProgram: ExperimentCurrentProgram = .none,
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
        self.windProgram = windProgram
        self.currentProgram = currentProgram
        self.outputContract = outputContract
        self.durationSeconds = durationSeconds
        self.sampleIntervalSeconds = sampleIntervalSeconds
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
        copy.windProgram = copy.windProgram.sanitized()
        copy.currentProgram = copy.currentProgram.sanitized()
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

/// Wind program v1. More complex piecewise programs belong in a later versioned contract.
struct ExperimentWindProgram: Codable, Equatable, Sendable {
    var trueWindDirectionDegrees: Double
    var speedKnots: Double

    static func steady(trueWindDirectionDegrees: Double, speedKnots: Double) -> ExperimentWindProgram {
        ExperimentWindProgram(
            trueWindDirectionDegrees: trueWindDirectionDegrees,
            speedKnots: speedKnots
        )
    }

    func sanitized() -> ExperimentWindProgram {
        ExperimentWindProgram(
            trueWindDirectionDegrees: Self.normalizedAngle(trueWindDirectionDegrees),
            speedKnots: Self.nonNegativeFinite(speedKnots)
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
