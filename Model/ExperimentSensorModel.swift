import Foundation

/// Fixed bias and uniform noise for one measured channel.
///
/// `bias` is added in the channel's own unit. `noiseAmplitude` is the half-width of a
/// uniform distribution, so each draw is in [-amplitude, +amplitude). Both default to zero.
struct SensorChannelError: Equatable, Sendable {
    var bias: Double = 0
    var noiseAmplitude: Double = 0
}

/// Errors for the primary instruments. The zero value leaves each reading equal to the
/// ideal apparent wind or the ideal speed through water.
struct SensorErrorConfiguration: Equatable, Sendable {
    var apparentWindSpeed = SensorChannelError()
    var apparentWindAngle = SensorChannelError()
    var speedThroughWater = SensorChannelError()
    var trueHeading = SensorChannelError()
    var magneticCompass = SensorChannelError()

    static let zero = SensorErrorConfiguration()
}

/// Which instruments publish a reading.
///
/// Defaults are on. A false flag makes that instrument nil and does not copy physical truth
/// into the gap. The experimental runtime maps the anemometer, speed log, gyro, and compass
/// switches here. The forward apparent wind still uses the physical heading.
struct InstrumentAvailability: Equatable, Sendable {
    var trueHeadingInstrument = true
    var magneticCompass = true
    var apparentWind = true
    var speedThroughWater = true
}

/// One sample of primary readings and the true wind calculated from them.
///
/// A nil primary reading means that input was missing or could not form an ideal value.
/// A nil derived wind means the primary readings were missing or not a valid water-relative
/// wind. Zero is a real reading.
struct ExperimentMeasurement: Equatable, Sendable {
    var apparentWindSpeedKnots: Double?
    var apparentWindAngleDegrees: Double?
    var speedThroughWaterKnots: Double?
    /// Measured true heading, degrees clockwise from true north in [0, 360).
    /// Nil when the physical heading was missing or non-finite, or the true-heading instrument is off.
    /// Zero is a real heading. This is not the magnetic compass.
    var trueHeadingDegrees: Double?
    /// Compass-card heading in [0, 360). Nil when the compass inputs are missing or the compass is off.
    /// This is the heading a future HDG sentence should put in its first field. Deviation and variation
    /// are the other two HDG fields and are not added into this number.
    var magneticCompassHeadingDegrees: Double?
    /// East-positive variation, degrees, copied through for the HDG variation field.
    var magneticVariationDegrees: Double?
    /// East-positive deviation, degrees, copied through for the HDG deviation field.
    var compassDeviationDegrees: Double?
    var trueWindSpeedKnots: Double?
    var trueWindAngleDegrees: Double?
    var trueWindDirectionDegrees: Double?
}

/// Physical inputs for one measurement. The model reads these values and does not store them.
///
/// True wind here is the water-relative wind: the direction the wind comes from, and the
/// speed through the air relative to the water. Speed over ground is not an input.
struct ExperimentSensorTruth: Equatable, Sendable {
    var trueWindSpeedKnots: Double?
    var trueHeadingDegrees: Double?
    var trueWindDirectionDegrees: Double?
    var speedThroughWaterKnots: Double?
    /// East-positive magnetic variation, degrees. Nil means the compass has no variation reference.
    /// Zero is a real variation. This is not course over ground.
    var magneticVariationDegrees: Double?
    /// East-positive compass deviation, degrees. Nil means the compass has no deviation reference.
    /// Zero is a real deviation.
    var compassDeviationDegrees: Double?

    init(
        trueWindSpeedKnots: Double? = nil,
        trueHeadingDegrees: Double? = nil,
        trueWindDirectionDegrees: Double? = nil,
        speedThroughWaterKnots: Double? = nil,
        magneticVariationDegrees: Double? = nil,
        compassDeviationDegrees: Double? = nil
    ) {
        self.trueWindSpeedKnots = trueWindSpeedKnots
        self.trueHeadingDegrees = trueHeadingDegrees
        self.trueWindDirectionDegrees = trueWindDirectionDegrees
        self.speedThroughWaterKnots = speedThroughWaterKnots
        self.magneticVariationDegrees = magneticVariationDegrees
        self.compassDeviationDegrees = compassDeviationDegrees
    }
}

/// Deterministic instrument error for an experiment. It is not consulted by the physics tick,
/// the NMEA snapshot, or the operator session.
///
/// The true-heading channel is a direct true-heading instrument. It observes physical true
/// heading. It is not a gyrocompass, a GNSS heading sensor, or an AHRS: none of those
/// dynamics are present. The magnetic compass is a separate channel and does not feed it.
/// Calculated true wind direction uses the true-heading instrument and does not fall back
/// to the physical heading or to the compass.
struct ExperimentSensorModel: Sendable {
    private var apparentWindSpeedGenerator: ExperimentRandomGenerator
    private var apparentWindAngleGenerator: ExperimentRandomGenerator
    private var speedThroughWaterGenerator: ExperimentRandomGenerator
    private var trueHeadingGenerator: ExperimentRandomGenerator
    private var magneticCompassGenerator: ExperimentRandomGenerator

    init(seed: UInt64) {
        // Channels 1...4 keep the M3.4.1c seeds. The magnetic compass is channel 5.
        apparentWindSpeedGenerator = Self.stream(seed: seed, channel: 1)
        apparentWindAngleGenerator = Self.stream(seed: seed, channel: 2)
        speedThroughWaterGenerator = Self.stream(seed: seed, channel: 3)
        trueHeadingGenerator = Self.stream(seed: seed, channel: 4)
        magneticCompassGenerator = Self.stream(seed: seed, channel: 5)
    }

    /// Instrument true-wind angle, degrees in [0, 360).
    ///
    /// This is `normalizeAngle(trueWindDirection - trueHeading)`, the same quantity as
    /// `computeTWA`. Zero is wind from dead ahead. Angles through 180 are wind from starboard.
    /// The polar table instead uses the unsigned fold
    /// `abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))`, which is in [0, 180].
    static func trueWindAngleDegrees(trueHeading: Double, trueWindDirection: Double) -> Double {
        normalizeAngle(trueWindDirection - trueHeading)
    }

    /// Ideal apparent wind in the boat frame. The equations match `computeAWS` and `computeAWA`
    /// when boat speed is speed through water.
    ///
    /// The wind vector points toward the direction the wind comes from. The boat's velocity
    /// through the water is added along the bow. A zero speed through water returns the true
    /// wind unchanged, including a zero true wind whose angle is still defined.
    static func apparentWind(
        trueWindSpeedKnots: Double,
        trueWindAngleDegrees: Double,
        speedThroughWaterKnots: Double
    ) -> (speedKnots: Double, angleDegrees: Double) {
        let angle = normalizeAngle(trueWindAngleDegrees)
        if speedThroughWaterKnots == 0 {
            return (trueWindSpeedKnots, angle)
        }
        let radians = toRadians(angle)
        let apparentX = trueWindSpeedKnots * cos(radians) + speedThroughWaterKnots
        let apparentY = trueWindSpeedKnots * sin(radians)
        return (
            hypot(apparentX, apparentY),
            normalizeAngle(toDegrees(atan2(apparentY, apparentX)))
        )
    }

    /// Inverse of `apparentWind`. Returns nil when a speed is negative or non-finite.
    ///
    /// A zero recovered wind vector has no direction, so the angle is nil and the speed is 0.
    /// That happens when the vessel is moving through still air. A stationary vessel keeps
    /// the apparent angle, including when both speeds are zero.
    static func derivedTrueWind(
        apparentWindSpeedKnots: Double,
        apparentWindAngleDegrees: Double,
        speedThroughWaterKnots: Double
    ) -> (speedKnots: Double, angleDegrees: Double?)? {
        guard apparentWindSpeedKnots.isFinite,
              apparentWindAngleDegrees.isFinite,
              speedThroughWaterKnots.isFinite,
              apparentWindSpeedKnots >= 0,
              speedThroughWaterKnots >= 0 else {
            return nil
        }
        if speedThroughWaterKnots == 0 {
            return (apparentWindSpeedKnots, normalizeAngle(apparentWindAngleDegrees))
        }
        let radians = toRadians(normalizeAngle(apparentWindAngleDegrees))
        let trueX = apparentWindSpeedKnots * cos(radians) - speedThroughWaterKnots
        let trueY = apparentWindSpeedKnots * sin(radians)
        let speed = hypot(trueX, trueY)
        guard speed > 0 else { return (0, nil) }
        return (speed, normalizeAngle(toDegrees(atan2(trueY, trueX))))
    }

    mutating func measure(
        _ truth: ExperimentSensorTruth,
        errors: SensorErrorConfiguration = .zero,
        availability: InstrumentAvailability = InstrumentAvailability()
    ) -> ExperimentMeasurement {
        let speedNoise = draw(error: errors.speedThroughWater, generator: &speedThroughWaterGenerator)
        let angleNoise = draw(error: errors.apparentWindAngle, generator: &apparentWindAngleGenerator)
        let windNoise = draw(error: errors.apparentWindSpeed, generator: &apparentWindSpeedGenerator)
        let headingNoise = draw(error: errors.trueHeading, generator: &trueHeadingGenerator)
        let compassNoise = draw(error: errors.magneticCompass, generator: &magneticCompassGenerator)

        let measuredSpeed = availability.speedThroughWater
            ? shifted(truth.speedThroughWaterKnots, bias: errors.speedThroughWater.bias, noise: speedNoise)
            : nil
        let ideal = idealApparentWind(truth)
        let measuredAngle = availability.apparentWind ? ideal.map {
            normalizeAngle($0.angleDegrees + finite(errors.apparentWindAngle.bias) + angleNoise)
        } : nil
        let measuredWind = availability.apparentWind ? ideal.map {
            $0.speedKnots + finite(errors.apparentWindSpeed.bias) + windNoise
        } : nil
        let measuredHeading = availability.trueHeadingInstrument
            ? Self.measuredTrueHeading(
                truth.trueHeadingDegrees,
                bias: errors.trueHeading.bias,
                noise: headingNoise
            )
            : nil
        let compassHeading = availability.magneticCompass
            ? Self.measuredMagneticCompass(
                trueHeadingDegrees: truth.trueHeadingDegrees,
                magneticVariationDegrees: truth.magneticVariationDegrees,
                compassDeviationDegrees: truth.compassDeviationDegrees,
                bias: errors.magneticCompass.bias,
                noise: compassNoise
            )
            : nil
        let derived = derivedWind(
            apparentSpeed: measuredWind,
            apparentAngle: measuredAngle,
            waterSpeed: measuredSpeed,
            heading: measuredHeading
        )
        return ExperimentMeasurement(
            apparentWindSpeedKnots: measuredWind,
            apparentWindAngleDegrees: measuredAngle,
            speedThroughWaterKnots: measuredSpeed,
            trueHeadingDegrees: measuredHeading,
            magneticCompassHeadingDegrees: compassHeading,
            magneticVariationDegrees: compassHeading == nil ? nil : truth.magneticVariationDegrees,
            compassDeviationDegrees: compassHeading == nil ? nil : truth.compassDeviationDegrees,
            trueWindSpeedKnots: derived?.speedKnots,
            trueWindAngleDegrees: derived?.angleDegrees,
            trueWindDirectionDegrees: derived?.directionDegrees
        )
    }

    /// Magnetic course, degrees in [0, 360). East-positive variation: `true − variation`.
    ///
    /// This matches the maneuver conversion in `SimulationEngine`. It does not apply deviation
    /// and it does not read course over ground.
    static func magneticHeadingDegrees(trueHeading: Double, magneticVariation: Double) -> Double {
        normalizeAngle(trueHeading - magneticVariation)
    }

    /// Compass card, degrees in [0, 360). East-positive deviation: `magnetic − deviation`.
    ///
    /// Applying deviation again when a receiver adds the HDG deviation field would double it.
    static func compassCardDegrees(magneticHeading: Double, compassDeviation: Double) -> Double {
        normalizeAngle(magneticHeading - compassDeviation)
    }

    /// Compass-card reading. Variation and deviation are each applied once, then bias and noise.
    ///
    /// A missing or non-finite true heading, variation, or deviation stays nil. The result is
    /// not replaced with true heading, magnetic heading, or course over ground.
    static func measuredMagneticCompass(
        trueHeadingDegrees: Double?,
        magneticVariationDegrees: Double?,
        compassDeviationDegrees: Double?,
        bias: Double,
        noise: Double
    ) -> Double? {
        guard let trueHeadingDegrees, trueHeadingDegrees.isFinite,
              let magneticVariationDegrees, magneticVariationDegrees.isFinite,
              let compassDeviationDegrees, compassDeviationDegrees.isFinite else {
            return nil
        }
        let magnetic = magneticHeadingDegrees(
            trueHeading: trueHeadingDegrees,
            magneticVariation: magneticVariationDegrees
        )
        let card = compassCardDegrees(magneticHeading: magnetic, compassDeviation: compassDeviationDegrees)
        let shifted = card + (bias.isFinite ? bias : 0) + noise
        guard shifted.isFinite else { return nil }
        return normalizeAngle(shifted)
    }

    /// Measured true heading in [0, 360). A missing or non-finite physical heading stays nil.
    ///
    /// `measured = normalizeAngle(physical + bias + noise)`. The result is not replaced
    /// with the physical heading when the sum is non-finite.
    static func measuredTrueHeading(_ physical: Double?, bias: Double, noise: Double) -> Double? {
        guard let physical, physical.isFinite else { return nil }
        let shifted = physical + (bias.isFinite ? bias : 0) + noise
        guard shifted.isFinite else { return nil }
        return normalizeAngle(shifted)
    }

    private static func stream(seed: UInt64, channel: UInt64) -> ExperimentRandomGenerator {
        ExperimentRandomGenerator(seed: seed ^ (0x9E37_79B9_7F4A_7C15 &* channel))
    }

    private func idealApparentWind(
        _ truth: ExperimentSensorTruth
    ) -> (speedKnots: Double, angleDegrees: Double)? {
        guard let wind = truth.trueWindSpeedKnots, wind.isFinite, wind >= 0,
              let heading = truth.trueHeadingDegrees, heading.isFinite,
              let direction = truth.trueWindDirectionDegrees, direction.isFinite,
              let water = truth.speedThroughWaterKnots, water.isFinite, water >= 0 else {
            return nil
        }
        return Self.apparentWind(
            trueWindSpeedKnots: wind,
            trueWindAngleDegrees: Self.trueWindAngleDegrees(trueHeading: heading, trueWindDirection: direction),
            speedThroughWaterKnots: water
        )
    }

    private func derivedWind(
        apparentSpeed: Double?,
        apparentAngle: Double?,
        waterSpeed: Double?,
        heading: Double?
    ) -> (speedKnots: Double?, angleDegrees: Double?, directionDegrees: Double?)? {
        guard let apparentSpeed, let apparentAngle, let waterSpeed,
              let wind = Self.derivedTrueWind(
                apparentWindSpeedKnots: apparentSpeed,
                apparentWindAngleDegrees: apparentAngle,
                speedThroughWaterKnots: waterSpeed
              ) else {
            return nil
        }
        let direction = wind.angleDegrees.flatMap { angle in
            heading.map { normalizeAngle($0 + angle) }
        }
        return (wind.speedKnots, wind.angleDegrees, direction)
    }

    private func shifted(_ truth: Double?, bias: Double, noise: Double) -> Double? {
        guard let truth, truth.isFinite else { return nil }
        return truth + finite(bias) + noise
    }

    /// One uniform draw in [-amplitude, +amplitude). The generator always advances.
    private func draw(
        error: SensorChannelError,
        generator: inout ExperimentRandomGenerator
    ) -> Double {
        let unit = generator.nextUnitInterval()
        let amplitude = abs(finite(error.noiseAmplitude))
        return (unit * 2 - 1) * amplitude
    }

    private func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
