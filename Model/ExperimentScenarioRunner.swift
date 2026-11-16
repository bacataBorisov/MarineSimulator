import Foundation

/// One simulation runtime prepared for a controlled experiment.
///
/// This value is not the operator session. Applying a scenario copies it and does not
/// write settings, the input mirror, or the product UI.
struct ExperimentRuntime {
    var state: SimulationState
    var config: SimulationConfig
}

/// Applies an `ExperimentScenario` to a clean baseline runtime.
///
/// The result is deterministic for a given scenario and baseline. The current program
/// stays on the scenario record and is not copied into vessel motion.
enum ExperimentScenarioRunner {
    static func prepare(_ scenario: ExperimentScenario, from baseline: ExperimentRuntime) -> ExperimentRuntime {
        let scenario = scenario.sanitized()
        var state = baseline.state
        state.enableExperimentRandomness(seed: scenario.seed)
        state.experimentInstruments = ExperimentInstrumentRuntime(seed: scenario.seed)
        state.hiddenPolarOverride = scenario.hiddenPolarProfile
        state.latestSnapshot = nil

        let direction = scenario.windProgram.trueWindDirectionDegrees
        let speed = scenario.windProgram.speedKnots
        state.twd.centerValue = direction
        state.twd.offset = 0
        state.twd.value = direction
        state.tws.centerValue = speed
        state.tws.offset = 0
        state.tws.value = speed
        state.environmentTruth.trueWindDirection = direction
        state.environmentTruth.trueWindSpeedKnots = speed
        state.environmentTruth.current = scenario.currentProgram
        state.vesselObservation.referenceProfile = scenario.referencePolarProfile

        let config = baseline.config.configuredForExperiment(
            weatherSourceMode: .manual,
            boatSpeedMode: .estimated,
            boatProfile: scenario.referencePolarProfile
        )
        return ExperimentRuntime(state: state, config: config)
    }
}

/// Measurement model owned by one prepared experiment.
///
/// `prepare` creates it from the scenario seed. Later ticks advance the same model.
/// Sentence publication reads the stored sample and does not draw again.
struct ExperimentInstrumentRuntime {
    var model: ExperimentSensorModel
    var errors = SensorErrorConfiguration.zero
    var latest: ExperimentMeasurement?
    var sampleTimestamp: Date?

    init(seed: UInt64) {
        model = ExperimentSensorModel(seed: seed)
    }

    /// Gyro measurement first. Otherwise the compass card plus its deviation and variation, once each.
    /// Neither path uses physical true heading or course over ground.
    static func resolvedTrueHeading(from measurement: ExperimentMeasurement) -> Double? {
        if let gyro = measurement.trueHeadingDegrees, gyro.isFinite {
            return normalizeAngle(gyro)
        }
        guard let compass = measurement.magneticCompassHeadingDegrees, compass.isFinite,
              let variation = measurement.magneticVariationDegrees, variation.isFinite,
              let deviation = measurement.compassDeviationDegrees, deviation.isFinite else {
            return nil
        }
        return normalizeAngle(compass + deviation + variation)
    }

    /// Magnetic course for a measured heading. Compass card plus deviation, or gyro minus variation.
    static func resolvedMagneticHeading(from measurement: ExperimentMeasurement) -> Double? {
        if let compass = measurement.magneticCompassHeadingDegrees, compass.isFinite,
           let deviation = measurement.compassDeviationDegrees, deviation.isFinite {
            return normalizeAngle(compass + deviation)
        }
        guard let gyro = measurement.trueHeadingDegrees, gyro.isFinite,
              let variation = measurement.magneticVariationDegrees, variation.isFinite else {
            return nil
        }
        return normalizeAngle(gyro - variation)
    }

    static func publication(from measurement: ExperimentMeasurement) -> ExperimentNavigationPublication {
        let resolved = resolvedTrueHeading(from: measurement)
        let direction = measurement.trueWindAngleDegrees.flatMap { angle in
            resolved.map { normalizeAngle($0 + angle) }
        }
        return ExperimentNavigationPublication(
            apparentWindSpeedKnots: publishedSpeed(measurement.apparentWindSpeedKnots),
            apparentWindAngleDegrees: finiteAngle(measurement.apparentWindAngleDegrees),
            trueWindSpeedKnots: publishedSpeed(measurement.trueWindSpeedKnots),
            trueWindAngleDegrees: finiteAngle(measurement.trueWindAngleDegrees),
            trueWindDirectionDegrees: finiteAngle(direction),
            trueHeadingDegrees: finiteAngle(measurement.trueHeadingDegrees),
            magneticCompassHeadingDegrees: finiteAngle(measurement.magneticCompassHeadingDegrees),
            magneticVariationDegrees: measurement.magneticCompassHeadingDegrees == nil
                ? nil
                : measurement.magneticVariationDegrees,
            compassDeviationDegrees: measurement.magneticCompassHeadingDegrees == nil
                ? nil
                : measurement.compassDeviationDegrees,
            resolvedTrueHeadingDegrees: finiteAngle(resolved),
            magneticHeadingDegrees: finiteAngle(resolvedMagneticHeading(from: measurement)),
            speedThroughWaterKnots: publishedSpeed(measurement.speedThroughWaterKnots)
        )
    }

    private static func publishedSpeed(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func finiteAngle(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return normalizeAngle(value)
    }
}

/// Values a prepared experiment may publish. Negative speeds are omitted.
struct ExperimentNavigationPublication: Equatable, Sendable {
    var apparentWindSpeedKnots: Double?
    var apparentWindAngleDegrees: Double?
    var trueWindSpeedKnots: Double?
    var trueWindAngleDegrees: Double?
    var trueWindDirectionDegrees: Double?
    var trueHeadingDegrees: Double?
    var magneticCompassHeadingDegrees: Double?
    var magneticVariationDegrees: Double?
    var compassDeviationDegrees: Double?
    var resolvedTrueHeadingDegrees: Double?
    var magneticHeadingDegrees: Double?
    var speedThroughWaterKnots: Double?
}
