import Foundation

/// Actual wind and water conditions. Sensor code must not write these.
struct EnvironmentTruth: Equatable {
    var trueWindDirection: Double?
    var trueWindSpeedKnots: Double?
    var seaTemperatureCelsius: Double?
    var airTemperatureCelsius: Double?
    var relativeHumidityPercent: Double?
    var airPressureHectopascals: Double?
    var depthMeters: Double?
}

/// Actual boat motion. Sensor code must not write these.
struct VesselTruth: Equatable {
    var latitude: Double = 0
    var longitude: Double = 0
    var magneticHeading: Double?
    var trueHeading: Double = 0
    var speedThroughWaterKnots: Double?
    var speedOverGroundKnots: Double = 0
    var courseOverGroundDegrees: Double = 0
    var acceptedCoordinateGeneration: UInt64 = 0
}

/// Deterministic pseudo-random source used only by explicitly seeded experiments.
/// The normal operator-facing simulator keeps using system randomness.
struct ExperimentRandomGenerator: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnitInterval() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Double(mixed >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

/// Mutable simulation state owned by the fast transmit queue while `isTransmitting`.
///
/// During off-main-thread simulation, this struct holds the authoritative copies of all
/// sensor values, GPS data, emission scheduling, and weather noise offsets. When the
/// simulation cycle completes, its contents are applied back to the main-thread properties
/// of ``NMEASimulator`` via `applyRuntimeToMain`.
struct SimulationState {
    var lastSimulationTickDate: Date?
    var lastSensorEvolutionDate: Date?
    var lastAppliedGPSCoordinateGeneration: UInt64 = 0
    var lastEmissionDates: [NMEASentenceType: Date] = [:]
    var pendingTransmissions: [PendingTransmission] = []
    var previousTurnReferenceHeading: Double?
    var sendRelativeWind = true
    var totalLogDistanceNm: Double = 0
    var totalTripDistanceNm: Double = 0
    var liveWeatherWindSpeedOffsetKt: Double = 0
    var liveWeatherWindDirectionOffsetDeg: Double = 0
    var liveWeatherNoiseBaselineFetchDate: Date?
    var environmentTruth = EnvironmentTruth()
    var vesselTruth = VesselTruth()
    var vesselObservation = VesselObservation()
    var sailConfiguration = SailConfiguration()
    /// Nil means the hidden polar is the selected boat profile.
    var hiddenPolarOverride: BoatProfile?
    var performance = PerformanceParameters()
    var scheduledPerformanceChanges: [ScheduledPerformanceChange] = []
    var activeManeuver: ActiveManeuver?
    var recoveryStartedAt: Date?
    /// True on a tick whose heading setpoint should follow the maneuver onto the dashboard.
    var publishManeuverHeadingSetpoint = false
    var gpsData: GPSData
    var twd: SimulatedValue
    var tws: SimulatedValue
    var speed: SimulatedValue
    var depth: SimulatedValue
    var seaTemp: SimulatedValue
    var airTemp: SimulatedValue
    var humidity: SimulatedValue
    var barometer: SimulatedValue
    var heading: SimulatedValue
    var gyroHeading: SimulatedValue
    var latestSnapshot: SimulationSnapshot?
    /// Nil preserves operator NMEA. A prepared experiment owns this model across ticks.
    var experimentInstruments: ExperimentInstrumentRuntime?
    /// Nil preserves the existing non-deterministic operator simulation.
    var experimentRandomGenerator: ExperimentRandomGenerator?
    /// Air, humidity, and pressure draws. Kept off the physical generator so those switches cannot move later samples.
    var measurementRandomGenerator: ExperimentRandomGenerator?

    mutating func enableExperimentRandomness(seed: UInt64) {
        experimentRandomGenerator = ExperimentRandomGenerator(seed: seed)
        measurementRandomGenerator = ExperimentRandomGenerator(seed: seed ^ 0xA5A5_A5A5_A5A5_A5A5)
    }

    mutating func disableExperimentRandomness() {
        experimentRandomGenerator = nil
    }

    init(from simulator: NMEASimulator) {
        gpsData = simulator.gpsData
        twd = simulator.twd
        tws = simulator.tws
        speed = simulator.speed
        depth = simulator.depth
        seaTemp = simulator.seaTemp
        airTemp = simulator.airTemp
        humidity = simulator.humidity
        barometer = simulator.barometer
        heading = simulator.heading
        gyroHeading = simulator.gyroHeading
        latestSnapshot = simulator.latestSnapshot
        liveWeatherWindSpeedOffsetKt = simulator.liveWeatherWindSpeedOffsetKt
        liveWeatherWindDirectionOffsetDeg = simulator.liveWeatherWindDirectionOffsetDeg
        liveWeatherNoiseBaselineFetchDate = simulator.liveWeatherNoiseBaselineFetchDate
        lastAppliedGPSCoordinateGeneration = simulator.gpsCoordinateSetpointGeneration
        environmentTruth = EnvironmentTruth(
            trueWindDirection: twd.value,
            trueWindSpeedKnots: tws.value,
            seaTemperatureCelsius: seaTemp.value,
            airTemperatureCelsius: airTemp.value,
            relativeHumidityPercent: humidity.value,
            airPressureHectopascals: barometer.value,
            depthMeters: depth.value
        )
        vesselTruth = VesselTruth(
            latitude: gpsData.latitude,
            longitude: gpsData.longitude,
            magneticHeading: heading.value,
            trueHeading: gyroHeading.value ?? heading.value ?? gpsData.courseOverGround,
            speedThroughWaterKnots: speed.value,
            speedOverGroundKnots: gpsData.speedOverGround,
            courseOverGroundDegrees: gpsData.courseOverGround,
            acceptedCoordinateGeneration: simulator.gpsCoordinateSetpointGeneration
        )
        sailConfiguration = simulator.sailConfiguration
        activeManeuver = simulator.activeManeuver
        performance.tackSpeedRetention = simulator.maneuverSettings.sanitized().tackSpeedRetention
        performance.gybeSpeedRetention = simulator.maneuverSettings.sanitized().gybeSpeedRetention
        vesselObservation = simulator.vesselObservation
        vesselObservation.sailConfiguration = simulator.sailConfiguration
        vesselObservation.referenceProfile = simulator.boatProfile
    }
}

enum SpeedResponse: String, Equatable, Sendable {
    case instant
    case firstOrder
}

enum ManeuverKind: String, Equatable, Sendable {
    case tack
    case gybe
}

enum ManeuverSide: String, Equatable, Sendable {
    case port
    case starboard
}

enum ManeuverCommand: Equatable, Sendable {
    case tack(ManeuverSide)
    case gybe(ManeuverSide)

    var kind: ManeuverKind {
        switch self {
        case .tack: return .tack
        case .gybe: return .gybe
        }
    }

    var side: ManeuverSide {
        switch self {
        case .tack(let side), .gybe(let side): return side
        }
    }
}

/// Operator maneuver settings. Nil duration uses the turn-size formula.
struct ManeuverOperatorSettings: Codable, Equatable, Sendable {
    var usesTackDuration = false
    var tackDurationSeconds: Double = 8
    var usesGybeDuration = false
    var gybeDurationSeconds: Double = 8
    var tackSpeedRetention: Double = 1
    var gybeSpeedRetention: Double = 1

    func sanitized() -> ManeuverOperatorSettings {
        var copy = self
        copy.tackDurationSeconds = Self.duration(tackDurationSeconds)
        copy.gybeDurationSeconds = Self.duration(gybeDurationSeconds)
        copy.tackSpeedRetention = Self.retention(tackSpeedRetention)
        copy.gybeSpeedRetention = Self.retention(gybeSpeedRetention)
        return copy
    }

    private static func duration(_ value: Double) -> Double {
        guard value.isFinite else { return 8 }
        return min(120, max(1, value))
    }

    private static func retention(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(1, max(0, value))
    }
}

enum ManeuverPhase: String, Equatable, Sendable {
    case idle
    case inProgress
    case recovery
}

enum ReefStep: String, Codable, Equatable, Sendable {
    case full
    case reef1
    case reef2
    case reef3
}

/// Hoisted sails. Identifiers are stable strings so a future inventory can use UUID strings
/// without linking this model to another application's types.
/// Changing this value does not change boat speed unless a hidden polar or a performance change is also applied.
struct SailConfiguration: Codable, Equatable, Sendable {
    var mainSailID: String?
    var headsailID: String?
    var downwindSailID: String?
    var mainsailReef: ReefStep = .full

    var hoistedIDs: [String] {
        [mainSailID, headsailID, downwindSailID].compactMap { $0 }
    }
}

/// Reports sail ids whose future inventory tag does not match the active performance tag.
/// The result is diagnostic. It does not change vessel speed.
enum SailPerformanceConsistency {
    static func mismatchedSailIDs(
        configuration: SailConfiguration,
        performanceTagBySailID: [String: String],
        activePerformanceTag: String?
    ) -> [String] {
        guard let activePerformanceTag else { return [] }
        return configuration.hoistedIDs.filter { id in
            guard let tag = performanceTagBySailID[id] else { return false }
            return tag != activePerformanceTag
        }
    }
}

struct PerformanceParameters: Equatable, Sendable {
    var speedResponse: SpeedResponse = .instant
    var hullFactor: Double = 1
    var sailFactor: Double = 1
    var trimEfficiency: Double = 1
    var seaStateFactor: Double = 1
    var accelerationTimeConstantSeconds: Double = 8
    var decelerationTimeConstantSeconds: Double = 4
    var tackSpeedRetention: Double = 1
    var gybeSpeedRetention: Double = 1

    func sanitized() -> PerformanceParameters {
        var copy = self
        copy.hullFactor = Self.factor(hullFactor)
        copy.sailFactor = Self.factor(sailFactor)
        copy.trimEfficiency = Self.factor(trimEfficiency)
        copy.seaStateFactor = Self.factor(seaStateFactor)
        copy.accelerationTimeConstantSeconds = Self.timeConstant(accelerationTimeConstantSeconds)
        copy.decelerationTimeConstantSeconds = Self.timeConstant(decelerationTimeConstantSeconds)
        copy.tackSpeedRetention = Self.retention(tackSpeedRetention)
        copy.gybeSpeedRetention = Self.retention(gybeSpeedRetention)
        return copy
    }

    private static func factor(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 3)
    }

    private static func timeConstant(_ value: Double) -> Double {
        guard value.isFinite else { return 8 }
        return min(max(value, 0), 600)
    }

    private static func retention(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }
}

struct ScheduledPerformanceChange: Equatable, Sendable {
    var simulationTime: Date
    var parameters: PerformanceParameters
}

struct ActiveManeuver: Equatable, Sendable {
    var kind: ManeuverKind
    var side: ManeuverSide = .port
    var startedAt: Date
    var duration: TimeInterval
    var fromTrueHeading: Double
    var toTrueHeading: Double
    var trueWindDirection: Double
    /// Signed sweep in degrees. May be outside −180…180 when the short arc would cross the wrong axis.
    var turnDelta: Double = 0
    var drivesHeading: Bool = false
}

/// What a future estimator may read. Hidden polar identity and performance factors are absent.
struct VesselObservation: Equatable, Sendable {
    var referenceProfile: BoatProfile = .beneteauFirst407
    var maneuverPhase: ManeuverPhase = .idle
    var maneuverKind: ManeuverKind?
    var sailConfiguration = SailConfiguration()
    var sailingState: ResolvedSailingState?
}

/// A sentence that was built but not yet transmitted, waiting for its stagger delay.
struct PendingTransmission {
    let sentence: String
    let dueDate: Date
}
