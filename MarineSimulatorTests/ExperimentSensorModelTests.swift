import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct ExperimentSensorModelTests {

    @Test
    func zeroErrorRecoversTrueWindOnBothTacks() {
        let cases: [(String, Double, Double, Double, Double)] = [
            ("headwind", 90, 90, 12, 6),
            ("starboard beam", 0, 90, 12, 6),
            ("port beam", 0, 270, 10, 5),
            ("starboard broad", 20, 155, 14, 7),
            ("port broad", 20, 245, 14, 7),
            ("downwind", 40, 220, 8, 4),
            ("stationary", 15, 200, 9, 0),
            ("calm and stopped", 10, 350, 0, 0),
            ("wrap from north", 350, 10, 11, 6.5)
        ]
        for item in cases {
            let truth = ExperimentSensorTruth(
                trueWindSpeedKnots: item.3,
                trueHeadingDegrees: item.1,
                trueWindDirectionDegrees: item.2,
                speedThroughWaterKnots: item.4
            )
            var model = ExperimentSensorModel(seed: 1)
            let measured = model.measure(truth)
            let angle = ExperimentSensorModel.trueWindAngleDegrees(
                trueHeading: item.1,
                trueWindDirection: item.2
            )
            expectAngle(measured.trueWindAngleDegrees, angle)
            expectClose(measured.trueWindSpeedKnots, item.3)
            expectAngle(measured.trueWindDirectionDegrees, normalizeAngle(item.2))
            expectAngle(measured.trueHeadingDegrees, normalizeAngle(item.1))
            #expect(measured.speedThroughWaterKnots == item.4)
        }
    }

    @Test
    func stillAirOnAMovingBoatHasNoRecoverableDirection() {
        var model = ExperimentSensorModel(seed: 1)
        let measured = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 0,
            trueHeadingDegrees: 90,
            trueWindDirectionDegrees: 180,
            speedThroughWaterKnots: 5
        ))
        #expect(measured.apparentWindSpeedKnots == 5)
        #expect(measured.apparentWindAngleDegrees == 0)
        #expect(measured.trueWindSpeedKnots == 0)
        #expect(measured.trueWindAngleDegrees == nil)
        #expect(measured.trueWindDirectionDegrees == nil)
    }

    @Test
    func apparentWindMatchesTheSentenceEquationsAndIgnoresSpeedOverGround() {
        let simulator = sensorSimulator()
        let samples: [(Double, Double, Double, Double)] = [
            (180, 12, 90, 6),
            (90, 10, 90, 0),
            (350, 8, 10, 4),
            (270, 15, 0, 7)
        ]
        for sample in samples {
            let angle = ExperimentSensorModel.trueWindAngleDegrees(
                trueHeading: sample.2,
                trueWindDirection: sample.0
            )
            let ideal = ExperimentSensorModel.apparentWind(
                trueWindSpeedKnots: sample.1,
                trueWindAngleDegrees: angle,
                speedThroughWaterKnots: sample.3
            )
            let snapshot = windSnapshot(
                direction: sample.0,
                speed: sample.1,
                heading: sample.2,
                waterSpeed: sample.3
            )
            let sentenceSpeed = simulator.computeAWS(from: snapshot) ?? -1
            let sentenceAngle = simulator.computeAWA(from: snapshot) ?? -1
            #expect(abs(sentenceSpeed - ideal.speedKnots) < 1e-9)
            #expect(abs(normalizeAngleTo180(sentenceAngle - ideal.angleDegrees)) < 1e-9)
            let usingAnotherSpeed = ExperimentSensorModel.apparentWind(
                trueWindSpeedKnots: sample.1,
                trueWindAngleDegrees: angle,
                speedThroughWaterKnots: sample.3 + 3
            )
            if sample.3 != 0 || sample.1 != 0 {
                #expect(usingAnotherSpeed.speedKnots != ideal.speedKnots || usingAnotherSpeed.angleDegrees != ideal.angleDegrees)
            }
        }
    }

    @Test
    func zeroHeadingErrorReproducesPhysicalHeadingIncludingZero() {
        var model = ExperimentSensorModel(seed: 5)
        let north = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 8,
            trueHeadingDegrees: 0,
            trueWindDirectionDegrees: 0,
            speedThroughWaterKnots: 0
        ))
        #expect(north.trueHeadingDegrees == 0)
        #expect(north.trueWindDirectionDegrees == 0)
        #expect(north.trueWindAngleDegrees == 0)
        #expect(north.apparentWindSpeedKnots == 8)
    }

    @Test
    func headingBiasChangesOnlyTrueWindDirection() {
        let truth = ExperimentSensorTruth(
            trueWindSpeedKnots: 12,
            trueHeadingDegrees: 30,
            trueWindDirectionDegrees: 120,
            speedThroughWaterKnots: 6
        )
        var plain = ExperimentSensorModel(seed: 2)
        let ideal = plain.measure(truth)
        var positive = ExperimentSensorModel(seed: 2)
        var plus = SensorErrorConfiguration.zero
        plus.trueHeading.bias = 15
        let starboard = positive.measure(truth, errors: plus)
        #expect(starboard.trueHeadingDegrees == 45)
        expectAngle(starboard.trueWindDirectionDegrees, normalizeAngle(120 + 15))
        #expect(starboard.trueWindSpeedKnots == ideal.trueWindSpeedKnots)
        #expect(starboard.trueWindAngleDegrees == ideal.trueWindAngleDegrees)
        #expect(starboard.apparentWindSpeedKnots == ideal.apparentWindSpeedKnots)
        #expect(starboard.apparentWindAngleDegrees == ideal.apparentWindAngleDegrees)
        #expect(starboard.speedThroughWaterKnots == ideal.speedThroughWaterKnots)

        var negative = ExperimentSensorModel(seed: 2)
        var minus = SensorErrorConfiguration.zero
        minus.trueHeading.bias = -20
        let port = negative.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 12,
            trueHeadingDegrees: 10,
            trueWindDirectionDegrees: 100,
            speedThroughWaterKnots: 6
        ), errors: minus)
        #expect(port.trueHeadingDegrees == 350)
        expectAngle(port.trueWindDirectionDegrees, normalizeAngle(100 - 20))

        var wrapped = ExperimentSensorModel(seed: 2)
        var east = SensorErrorConfiguration.zero
        east.trueHeading.bias = 20
        let acrossNorth = wrapped.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 12,
            trueHeadingDegrees: 350,
            trueWindDirectionDegrees: 10,
            speedThroughWaterKnots: 6
        ), errors: east)
        #expect(acrossNorth.trueHeadingDegrees == 10)
        expectAngle(acrossNorth.trueWindDirectionDegrees, normalizeAngle(10 + 20))
    }

    @Test
    func headingNoiseStaysInsideItsAmplitude() {
        let truth = ExperimentSensorTruth(
            trueWindSpeedKnots: 12,
            trueHeadingDegrees: 30,
            trueWindDirectionDegrees: 120,
            speedThroughWaterKnots: 6
        )
        var plain = ExperimentSensorModel(seed: 6)
        let ideal = plain.measure(truth)
        var errors = SensorErrorConfiguration.zero
        errors.trueHeading.noiseAmplitude = 4
        var model = ExperimentSensorModel(seed: 6)
        var sawNoise = false
        for _ in 0..<16 {
            let measured = model.measure(truth, errors: errors)
            let delta = normalizeAngleTo180((measured.trueHeadingDegrees ?? .nan) - 30)
            #expect(abs(delta) <= 4)
            #expect(measured.trueHeadingDegrees != nil)
            #expect(measured.trueWindSpeedKnots == ideal.trueWindSpeedKnots)
            #expect(measured.trueWindAngleDegrees == ideal.trueWindAngleDegrees)
            #expect(measured.apparentWindSpeedKnots == ideal.apparentWindSpeedKnots)
            #expect(measured.apparentWindAngleDegrees == ideal.apparentWindAngleDegrees)
            sawNoise = sawNoise || delta != 0
        }
        #expect(sawNoise)
    }

    @Test
    func headingStreamsStayIndependentOfTheWindStreams() {
        var windErrors = SensorErrorConfiguration.zero
        windErrors.apparentWindSpeed.noiseAmplitude = 0.4
        windErrors.apparentWindAngle.noiseAmplitude = 5
        windErrors.speedThroughWater.noiseAmplitude = 0.2
        var withHeading = windErrors
        withHeading.trueHeading.noiseAmplitude = 8
        withHeading.trueHeading.bias = 3
        let calm = sequence(seed: 14, count: 8, truth: sampleTruth, errors: windErrors)
        let noisy = sequence(seed: 14, count: 8, truth: sampleTruth, errors: withHeading)
        #expect(calm.map(\.apparentWindSpeedKnots) == noisy.map(\.apparentWindSpeedKnots))
        #expect(calm.map(\.apparentWindAngleDegrees) == noisy.map(\.apparentWindAngleDegrees))
        #expect(calm.map(\.speedThroughWaterKnots) == noisy.map(\.speedThroughWaterKnots))
        #expect(calm.map(\.trueWindSpeedKnots) == noisy.map(\.trueWindSpeedKnots))
        #expect(calm.map(\.trueWindAngleDegrees) == noisy.map(\.trueWindAngleDegrees))
        #expect(calm.map(\.trueHeadingDegrees) != noisy.map(\.trueHeadingDegrees))
        #expect(calm.map(\.trueWindDirectionDegrees) != noisy.map(\.trueWindDirectionDegrees))

        let repeated = sequence(seed: 14, count: 8, truth: sampleTruth, errors: withHeading)
        let otherSeed = sequence(seed: 15, count: 8, truth: sampleTruth, errors: withHeading)
        #expect(noisy.map(\.trueHeadingDegrees) == repeated.map(\.trueHeadingDegrees))
        #expect(noisy.map(\.trueHeadingDegrees) != otherSeed.map(\.trueHeadingDegrees))
    }

    @Test
    func windChannelDrawsStillMatchTheOriginalSeedFormula() {
        let seed: UInt64 = 21
        let mix: UInt64 = 0x9E37_79B9_7F4A_7C15
        var windGenerator = ExperimentRandomGenerator(seed: seed ^ (mix &* 1))
        var angleGenerator = ExperimentRandomGenerator(seed: seed ^ (mix &* 2))
        var speedGenerator = ExperimentRandomGenerator(seed: seed ^ (mix &* 3))
        var headingGenerator = ExperimentRandomGenerator(seed: seed ^ (mix &* 4))
        var errors = SensorErrorConfiguration.zero
        errors.apparentWindSpeed.noiseAmplitude = 1
        errors.apparentWindAngle.noiseAmplitude = 10
        errors.speedThroughWater.noiseAmplitude = 0.5
        errors.trueHeading.noiseAmplitude = 7
        let ideal = ExperimentSensorModel.apparentWind(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: 90,
            speedThroughWaterKnots: 6
        )
        var model = ExperimentSensorModel(seed: seed)
        for _ in 0..<8 {
            let measured = model.measure(sampleTruth, errors: errors)
            let windNoise = (windGenerator.nextUnitInterval() * 2 - 1) * 1
            let angleNoise = (angleGenerator.nextUnitInterval() * 2 - 1) * 10
            let speedNoise = (speedGenerator.nextUnitInterval() * 2 - 1) * 0.5
            let headingNoise = (headingGenerator.nextUnitInterval() * 2 - 1) * 7
            #expect(measured.apparentWindSpeedKnots == ideal.speedKnots + windNoise)
            expectAngle(measured.apparentWindAngleDegrees, normalizeAngle(ideal.angleDegrees + angleNoise))
            #expect(measured.speedThroughWaterKnots == 6 + speedNoise)
            expectAngle(measured.trueHeadingDegrees, normalizeAngle(headingNoise))
        }
    }

    @Test
    func missingOrNonFiniteHeadingDoesNotBorrowPhysicalTruth() {
        var model = ExperimentSensorModel(seed: 3)
        let missing = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 12,
            trueHeadingDegrees: nil,
            trueWindDirectionDegrees: 90,
            speedThroughWaterKnots: 6
        ))
        #expect(missing.trueHeadingDegrees == nil)
        #expect(missing.trueWindDirectionDegrees == nil)
        #expect(missing.apparentWindSpeedKnots == nil)
        #expect(missing.apparentWindAngleDegrees == nil)
        #expect(missing.trueWindSpeedKnots == nil)
        #expect(missing.trueWindAngleDegrees == nil)
        #expect(missing.speedThroughWaterKnots == 6)

        let invalidNumbers = [Double.nan, Double.infinity, -Double.infinity]
        for heading in invalidNumbers {
            let rejected = model.measure(ExperimentSensorTruth(
                trueWindSpeedKnots: 12,
                trueHeadingDegrees: heading,
                trueWindDirectionDegrees: 90,
                speedThroughWaterKnots: 6
            ))
            #expect(rejected.trueHeadingDegrees == nil)
            #expect(rejected.trueWindDirectionDegrees == nil)
            #expect(rejected.trueHeadingDegrees != 90)
            #expect(rejected.speedThroughWaterKnots == 6)
        }
    }

    @Test
    func idealGyroHeadingEqualsPhysicalTrueHeading() {
        var model = ExperimentSensorModel(seed: 5)
        let measured = model.measure(compassTruth(trueHeading: 90, direction: 180, variation: 12, deviation: 4))
        #expect(measured.trueHeadingDegrees == 90)
        #expect(measured.magneticCompassHeadingDegrees != 90)
        expectAngle(measured.trueWindDirectionDegrees, 180)
    }

    @Test
    func magneticCompassUsesVariationOnceAndDeviationOnce() {
        let gps = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 200)
        let time = Date(timeIntervalSince1970: 1_800_030_000)
        let variation = SimulationEngine.simulatedMagneticVariation(for: gps, at: time)
        let trueHeading = 90.0
        let magnetic = ExperimentSensorModel.magneticHeadingDegrees(
            trueHeading: trueHeading,
            magneticVariation: variation
        )
        #expect(magnetic == normalizeAngle(trueHeading - variation))
        let deviation = SimulationEngine.simulatedCompassDeviation(heading: magnetic)
        let card = ExperimentSensorModel.compassCardDegrees(
            magneticHeading: magnetic,
            compassDeviation: deviation
        )
        #expect(card == normalizeAngle(magnetic - deviation))
        expectAngle(normalizeAngle(card + deviation + variation), trueHeading)

        #expect(ExperimentSensorModel.magneticHeadingDegrees(trueHeading: 90, magneticVariation: 10) == 80)
        #expect(ExperimentSensorModel.magneticHeadingDegrees(trueHeading: 10, magneticVariation: -8) == 18)
        #expect(ExperimentSensorModel.compassCardDegrees(magneticHeading: 80, compassDeviation: 4) == 76)
        #expect(ExperimentSensorModel.compassCardDegrees(magneticHeading: 2, compassDeviation: -4) == 6)
        #expect(ExperimentSensorModel.compassCardDegrees(magneticHeading: 0, compassDeviation: 0) == 0)
        #expect(ExperimentSensorModel.magneticHeadingDegrees(trueHeading: 5, magneticVariation: 10) == 355)

        var model = ExperimentSensorModel(seed: 1)
        let measured = model.measure(compassTruth(trueHeading: 90, direction: 180, variation: variation, deviation: deviation))
        #expect(measured.magneticCompassHeadingDegrees == card)
        #expect(measured.magneticVariationDegrees == variation)
        #expect(measured.compassDeviationDegrees == deviation)
        let liveHDGHeadingField = magnetic
        if deviation != 0 {
            #expect(measured.magneticCompassHeadingDegrees != liveHDGHeadingField)
        }
    }

    @Test
    func compassBiasDoesNotMoveTheGyroOrTrueWindDirection() {
        let truth = compassTruth(trueHeading: 30, direction: 120, variation: 6, deviation: 2)
        var plain = ExperimentSensorModel(seed: 2)
        let ideal = plain.measure(truth)
        var positive = ExperimentSensorModel(seed: 2)
        var plus = SensorErrorConfiguration.zero
        plus.magneticCompass.bias = 15
        let starboard = positive.measure(truth, errors: plus)
        expectAngle(starboard.magneticCompassHeadingDegrees, normalizeAngle((ideal.magneticCompassHeadingDegrees ?? .nan) + 15))
        #expect(starboard.trueHeadingDegrees == ideal.trueHeadingDegrees)
        #expect(starboard.trueWindDirectionDegrees == ideal.trueWindDirectionDegrees)
        #expect(starboard.trueWindSpeedKnots == ideal.trueWindSpeedKnots)
        #expect(starboard.apparentWindSpeedKnots == ideal.apparentWindSpeedKnots)

        var negative = ExperimentSensorModel(seed: 2)
        var minus = SensorErrorConfiguration.zero
        minus.magneticCompass.bias = -20
        let wrapped = negative.measure(
            compassTruth(trueHeading: 10, direction: 40, variation: 0, deviation: 0),
            errors: minus
        )
        #expect(wrapped.magneticCompassHeadingDegrees == 350)
        #expect(wrapped.trueHeadingDegrees == 10)

        var acrossNorth = ExperimentSensorModel(seed: 2)
        var east = SensorErrorConfiguration.zero
        east.magneticCompass.bias = 20
        let north = acrossNorth.measure(
            compassTruth(trueHeading: 350, direction: 10, variation: 0, deviation: 0),
            errors: east
        )
        #expect(north.magneticCompassHeadingDegrees == 10)
        expectAngle(north.trueWindDirectionDegrees, 10)
    }

    @Test
    func gyroBiasDoesNotMoveTheCompass() {
        let truth = compassTruth(trueHeading: 30, direction: 120, variation: 6, deviation: 2)
        var plain = ExperimentSensorModel(seed: 2)
        let ideal = plain.measure(truth)
        var shifted = ExperimentSensorModel(seed: 2)
        var errors = SensorErrorConfiguration.zero
        errors.trueHeading.bias = 15
        let measured = shifted.measure(truth, errors: errors)
        #expect(measured.trueHeadingDegrees == 45)
        expectAngle(measured.trueWindDirectionDegrees, normalizeAngle(120 + 15))
        #expect(measured.magneticCompassHeadingDegrees == ideal.magneticCompassHeadingDegrees)
        #expect(measured.trueWindSpeedKnots == ideal.trueWindSpeedKnots)
        #expect(measured.trueWindAngleDegrees == ideal.trueWindAngleDegrees)
        #expect(measured.apparentWindAngleDegrees == ideal.apparentWindAngleDegrees)
    }

    @Test
    func compassAndGyroNoiseUseSeparateStreams() {
        let truth = compassTruth(trueHeading: 40, direction: 100, variation: 5, deviation: -3)
        var compassErrors = SensorErrorConfiguration.zero
        compassErrors.magneticCompass.noiseAmplitude = 6
        var gyroErrors = SensorErrorConfiguration.zero
        gyroErrors.trueHeading.noiseAmplitude = 4
        var both = compassErrors
        both.trueHeading.noiseAmplitude = 4
        let compassOnly = sequence(seed: 18, count: 8, truth: truth, errors: compassErrors)
        let gyroOnly = sequence(seed: 18, count: 8, truth: truth, errors: gyroErrors)
        let together = sequence(seed: 18, count: 8, truth: truth, errors: both)
        #expect(compassOnly.map(\.magneticCompassHeadingDegrees) == together.map(\.magneticCompassHeadingDegrees))
        #expect(gyroOnly.map(\.trueHeadingDegrees) == together.map(\.trueHeadingDegrees))
        #expect(compassOnly.map(\.trueHeadingDegrees) != together.map(\.trueHeadingDegrees))
        #expect(gyroOnly.map(\.magneticCompassHeadingDegrees) != together.map(\.magneticCompassHeadingDegrees))
        #expect(together == sequence(seed: 18, count: 8, truth: truth, errors: both))
        #expect(together.map(\.magneticCompassHeadingDegrees) != sequence(seed: 19, count: 8, truth: truth, errors: both).map(\.magneticCompassHeadingDegrees))

        var wind = SensorErrorConfiguration.zero
        wind.apparentWindSpeed.noiseAmplitude = 0.4
        wind.apparentWindAngle.noiseAmplitude = 5
        wind.speedThroughWater.noiseAmplitude = 0.2
        var windAndCompass = wind
        windAndCompass.magneticCompass.noiseAmplitude = 9
        windAndCompass.magneticCompass.bias = 2
        let calm = sequence(seed: 21, count: 6, truth: sampleTruth, errors: wind)
        let noisyCompass = sequence(seed: 21, count: 6, truth: sampleTruth, errors: windAndCompass)
        #expect(calm.map(\.apparentWindSpeedKnots) == noisyCompass.map(\.apparentWindSpeedKnots))
        #expect(calm.map(\.apparentWindAngleDegrees) == noisyCompass.map(\.apparentWindAngleDegrees))
        #expect(calm.map(\.speedThroughWaterKnots) == noisyCompass.map(\.speedThroughWaterKnots))
        #expect(calm.map(\.trueHeadingDegrees) == noisyCompass.map(\.trueHeadingDegrees))
    }

    @Test
    func unavailableHeadingInstrumentsDoNotBorrowPhysicalTruth() {
        let truth = compassTruth(trueHeading: 90, direction: 180, variation: 7, deviation: 1.2)
        var model = ExperimentSensorModel(seed: 4)
        var gyroOff = InstrumentAvailability()
        gyroOff.trueHeadingInstrument = false
        let withoutGyro = model.measure(truth, availability: gyroOff)
        #expect(withoutGyro.trueHeadingDegrees == nil)
        #expect(withoutGyro.trueWindDirectionDegrees == nil)
        #expect(withoutGyro.apparentWindSpeedKnots != nil)
        #expect(withoutGyro.trueWindSpeedKnots != nil)
        #expect(withoutGyro.trueWindAngleDegrees != nil)
        #expect(withoutGyro.magneticCompassHeadingDegrees != nil)
        #expect(withoutGyro.trueHeadingDegrees != truth.trueHeadingDegrees)

        var compassOff = InstrumentAvailability()
        compassOff.magneticCompass = false
        let withoutCompass = model.measure(truth, availability: compassOff)
        #expect(withoutCompass.magneticCompassHeadingDegrees == nil)
        #expect(withoutCompass.magneticVariationDegrees == nil)
        #expect(withoutCompass.compassDeviationDegrees == nil)
        #expect(withoutCompass.trueHeadingDegrees == 90)
        #expect(withoutCompass.trueWindDirectionDegrees != nil)

        let missingVariation = model.measure(compassTruth(trueHeading: 90, direction: 180, variation: nil, deviation: 0))
        #expect(missingVariation.magneticCompassHeadingDegrees == nil)
        #expect(missingVariation.trueHeadingDegrees == 90)
        let badDeviation = model.measure(compassTruth(trueHeading: 90, direction: 180, variation: 4, deviation: .nan))
        #expect(badDeviation.magneticCompassHeadingDegrees == nil)
        #expect(badDeviation.trueHeadingDegrees == 90)
        #expect(badDeviation.magneticCompassHeadingDegrees != 200)
    }

    @Test
    func primaryBiasIsAppliedBeforeTheInverse() {
        let truth = ExperimentSensorTruth(
            trueWindSpeedKnots: 12,
            trueHeadingDegrees: 0,
            trueWindDirectionDegrees: 90,
            speedThroughWaterKnots: 6
        )
        let angle = ExperimentSensorModel.trueWindAngleDegrees(trueHeading: 0, trueWindDirection: 90)
        let ideal = ExperimentSensorModel.apparentWind(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: angle,
            speedThroughWaterKnots: 6
        )

        var wind = ExperimentSensorModel(seed: 4)
        var windErrors = SensorErrorConfiguration.zero
        windErrors.apparentWindSpeed.bias = 1.5
        let windSample = wind.measure(truth, errors: windErrors)
        #expect(windSample.apparentWindSpeedKnots == ideal.speedKnots + 1.5)
        #expect(windSample.trueWindSpeedKnots != 12)

        var angleModel = ExperimentSensorModel(seed: 4)
        var angleErrors = SensorErrorConfiguration.zero
        angleErrors.apparentWindAngle.bias = -20
        let angleSample = angleModel.measure(truth, errors: angleErrors)
        expectAngle(angleSample.apparentWindAngleDegrees, normalizeAngle(ideal.angleDegrees - 20))
        #expect(angleSample.trueWindAngleDegrees != angle)

        var speed = ExperimentSensorModel(seed: 4)
        var speedErrors = SensorErrorConfiguration.zero
        speedErrors.speedThroughWater.bias = 0.5
        let speedSample = speed.measure(truth, errors: speedErrors)
        #expect(speedSample.speedThroughWaterKnots == 6.5)
        #expect(speedSample.trueWindSpeedKnots != 12)
    }

    @Test
    func zeroRemainsAReadingAndInvalidWindDoesNotBorrowTheTruth() {
        var model = ExperimentSensorModel(seed: 3)
        let calm = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 0,
            trueHeadingDegrees: 90,
            trueWindDirectionDegrees: 90,
            speedThroughWaterKnots: 0
        ))
        #expect(calm.apparentWindSpeedKnots == 0)
        #expect(calm.apparentWindAngleDegrees == 0)
        #expect(calm.speedThroughWaterKnots == 0)
        #expect(calm.trueWindSpeedKnots == 0)
        #expect(calm.trueWindAngleDegrees == 0)

        var negative = ExperimentSensorModel(seed: 3)
        var errors = SensorErrorConfiguration.zero
        errors.apparentWindSpeed.bias = -30
        let rejected = negative.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 4,
            trueHeadingDegrees: 0,
            trueWindDirectionDegrees: 0,
            speedThroughWaterKnots: 2
        ), errors: errors)
        #expect((rejected.apparentWindSpeedKnots ?? 0) < 0)
        #expect(rejected.trueWindSpeedKnots == nil)
        #expect(rejected.trueWindAngleDegrees == nil)
        #expect(rejected.trueWindDirectionDegrees == nil)

        let missing = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: nil,
            trueHeadingDegrees: 10,
            trueWindDirectionDegrees: 40,
            speedThroughWaterKnots: 0
        ))
        #expect(missing.apparentWindSpeedKnots == nil)
        #expect(missing.apparentWindAngleDegrees == nil)
        #expect(missing.trueWindSpeedKnots == nil)
        #expect(missing.speedThroughWaterKnots == 0)

        let reversedLog = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: 8,
            trueHeadingDegrees: 0,
            trueWindDirectionDegrees: 90,
            speedThroughWaterKnots: -1
        ))
        #expect(reversedLog.apparentWindSpeedKnots == nil)
        #expect(reversedLog.speedThroughWaterKnots == -1)
        #expect(reversedLog.trueWindSpeedKnots == nil)
    }

    @Test
    func noiseStaysInsideItsAmplitudeAndStreamsStayIndependent() {
        let truth = sampleTruth
        var errors = SensorErrorConfiguration.zero
        errors.apparentWindSpeed.noiseAmplitude = 0.4
        errors.apparentWindAngle.noiseAmplitude = 5
        errors.speedThroughWater.noiseAmplitude = 0.2
        let ideal = ExperimentSensorModel.apparentWind(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: 90,
            speedThroughWaterKnots: 6
        )
        var model = ExperimentSensorModel(seed: 9)
        var sawWind = false
        var sawAngle = false
        var sawSpeed = false
        for _ in 0..<12 {
            let measured = model.measure(truth, errors: errors)
            let windError = (measured.apparentWindSpeedKnots ?? 999) - ideal.speedKnots
            let angleError = normalizeAngleTo180((measured.apparentWindAngleDegrees ?? 999) - ideal.angleDegrees)
            let speedError = (measured.speedThroughWaterKnots ?? 999) - 6
            #expect(abs(windError) <= 0.4)
            #expect(abs(angleError) <= 5)
            #expect(abs(speedError) <= 0.2)
            sawWind = sawWind || windError != 0
            sawAngle = sawAngle || angleError != 0
            sawSpeed = sawSpeed || speedError != 0
        }
        #expect(sawWind)
        #expect(sawAngle)
        #expect(sawSpeed)

        var changed = errors
        changed.apparentWindSpeed.noiseAmplitude = 5
        changed.apparentWindSpeed.bias = 3
        let first = sequence(seed: 4, count: 6, truth: truth, errors: errors)
        let second = sequence(seed: 4, count: 6, truth: truth, errors: changed)
        #expect(first.map(\.apparentWindAngleDegrees) == second.map(\.apparentWindAngleDegrees))
        #expect(first.map(\.speedThroughWaterKnots) == second.map(\.speedThroughWaterKnots))
        #expect(first.map(\.apparentWindSpeedKnots) != second.map(\.apparentWindSpeedKnots))
        #expect(first.map(\.trueWindSpeedKnots) != second.map(\.trueWindSpeedKnots))
    }

    @Test
    func theSameSeedRepeatsAndANewSeedDoesNot() {
        let first = sequence(seed: 11, count: 6, truth: sampleTruth, errors: noisyErrors)
        let repeatRun = sequence(seed: 11, count: 6, truth: sampleTruth, errors: noisyErrors)
        let other = sequence(seed: 12, count: 6, truth: sampleTruth, errors: noisyErrors)
        #expect(first == repeatRun)
        #expect(first != other)

        let scenario = ExperimentScenario(
            name: "Sensor",
            seed: 44,
            referencePolarProfile: .beneteauFirst407,
            hiddenPolarProfile: .nimana,
            windProgram: .steady(trueWindDirectionDegrees: 180, speedKnots: 12),
            durationSeconds: 60,
            sampleIntervalSeconds: 1
        )
        let truth = ExperimentSensorTruth(
            trueWindSpeedKnots: scenario.windProgram.speedKnots,
            trueHeadingDegrees: 90,
            trueWindDirectionDegrees: scenario.windProgram.trueWindDirectionDegrees,
            speedThroughWaterKnots: 6
        )
        #expect(sequence(seed: scenario.seed, count: 5, truth: truth, errors: noisyErrors)
            == sequence(seed: scenario.seed, count: 5, truth: truth, errors: noisyErrors))
        #expect(scenario.hiddenPolarProfile == .nimana)
    }

    @Test
    func measuringLeavesPhysicalTruthAndTheVesselTrackAlone() {
        var environment = EnvironmentTruth(
            trueWindDirection: 180,
            trueWindSpeedKnots: 12,
            seaTemperatureCelsius: 16,
            airTemperatureCelsius: nil,
            relativeHumidityPercent: nil,
            airPressureHectopascals: nil,
            depthMeters: 20
        )
        var vessel = VesselTruth(
            latitude: 43,
            longitude: 28,
            magneticHeading: 90,
            trueHeading: 90,
            speedThroughWaterKnots: 6,
            speedOverGroundKnots: 6,
            courseOverGroundDegrees: 90
        )
        let originalEnvironment = environment
        let originalVessel = vessel
        var headingErrors = noisyErrors
        headingErrors.trueHeading.bias = 25
        headingErrors.trueHeading.noiseAmplitude = 5
        headingErrors.magneticCompass.bias = 12
        headingErrors.magneticCompass.noiseAmplitude = 3
        var model = ExperimentSensorModel(seed: 30)
        let reading = model.measure(ExperimentSensorTruth(
            trueWindSpeedKnots: environment.trueWindSpeedKnots,
            trueHeadingDegrees: vessel.trueHeading,
            trueWindDirectionDegrees: environment.trueWindDirection,
            speedThroughWaterKnots: vessel.speedThroughWaterKnots,
            magneticVariationDegrees: 4,
            compassDeviationDegrees: 1
        ), errors: headingErrors)
        #expect(environment == originalEnvironment)
        #expect(vessel == originalVessel)
        #expect(vessel.trueHeading == 90)
        #expect(vessel.magneticHeading == 90)
        #expect(reading.trueHeadingDegrees != 90)
        #expect(reading.magneticCompassHeadingDegrees != vessel.magneticHeading)

        let start = Date(timeIntervalSince1970: 1_800_030_000)
        var observed = sensorState()
        var untouched = observed
        let config = sensorConfig()
        for step in 0...3 {
            let time = start.addingTimeInterval(TimeInterval(step))
            _ = SimulationEngine.tickSimulation(
                state: &observed, config: config, at: time,
                liveWeatherValueGenerator: { base, _, _, _ in base }
            )
            _ = model.measure(ExperimentSensorTruth(
                trueWindSpeedKnots: observed.environmentTruth.trueWindSpeedKnots,
                trueHeadingDegrees: observed.vesselTruth.trueHeading,
                trueWindDirectionDegrees: observed.environmentTruth.trueWindDirection,
                speedThroughWaterKnots: observed.vesselTruth.speedThroughWaterKnots,
                magneticVariationDegrees: 4,
                compassDeviationDegrees: 1
            ), errors: headingErrors)
            _ = SimulationEngine.tickSimulation(
                state: &untouched, config: config, at: time,
                liveWeatherValueGenerator: { base, _, _, _ in base }
            )
        }
        #expect(observed.vesselTruth == untouched.vesselTruth)
        #expect(observed.environmentTruth == untouched.environmentTruth)
        #expect(observed.hiddenPolarOverride == untouched.hiddenPolarOverride)
        #expect(observed.latestSnapshot?.magneticHeading == untouched.latestSnapshot?.magneticHeading)
        #expect(observed.latestSnapshot?.gyroHeading == untouched.latestSnapshot?.gyroHeading)
        #expect(observed.latestSnapshot?.compassDeviation == untouched.latestSnapshot?.compassDeviation)
        #expect(observed.latestSnapshot?.magneticVariation == untouched.latestSnapshot?.magneticVariation)
        #expect(observed.latestSnapshot?.windDirectionTrue == untouched.latestSnapshot?.windDirectionTrue)
    }
}

private func compassTruth(
    trueHeading: Double,
    direction: Double,
    variation: Double?,
    deviation: Double?
) -> ExperimentSensorTruth {
    ExperimentSensorTruth(
        trueWindSpeedKnots: 12,
        trueHeadingDegrees: trueHeading,
        trueWindDirectionDegrees: direction,
        speedThroughWaterKnots: 6,
        magneticVariationDegrees: variation,
        compassDeviationDegrees: deviation
    )
}

private let sampleTruth = ExperimentSensorTruth(
    trueWindSpeedKnots: 12,
    trueHeadingDegrees: 0,
    trueWindDirectionDegrees: 90,
    speedThroughWaterKnots: 6
)

private var noisyErrors: SensorErrorConfiguration {
    var errors = SensorErrorConfiguration.zero
    errors.apparentWindSpeed.noiseAmplitude = 0.8
    errors.apparentWindSpeed.bias = 0.3
    errors.apparentWindAngle.noiseAmplitude = 4
    errors.apparentWindAngle.bias = 1
    errors.speedThroughWater.noiseAmplitude = 0.25
    errors.speedThroughWater.bias = -0.1
    return errors
}

private func sequence(
    seed: UInt64,
    count: Int,
    truth: ExperimentSensorTruth,
    errors: SensorErrorConfiguration
) -> [ExperimentMeasurement] {
    var model = ExperimentSensorModel(seed: seed)
    return (0..<count).map { _ in model.measure(truth, errors: errors) }
}

private func expectClose(_ value: Double?, _ expected: Double) {
    let actual = value ?? .nan
    #expect(abs(actual - expected) <= 1e-9)
}

private func expectAngle(_ value: Double?, _ expected: Double) {
    let actual = value ?? .nan
    #expect(abs(normalizeAngleTo180(actual - expected)) <= 1e-9)
}

private func windSnapshot(direction: Double, speed: Double, heading: Double, waterSpeed: Double) -> SimulationSnapshot {
    SimulationSnapshot(
        timestamp: Date(timeIntervalSince1970: 0),
        windDirectionTrue: direction,
        windSpeedTrue: speed,
        magneticHeading: heading,
        gyroHeading: nil,
        magneticVariation: 0,
        compassDeviation: 0,
        boatSpeed: waterSpeed,
        depth: nil,
        seaTemperature: nil,
        airTemperature: nil,
        relativeHumidity: nil,
        airPressure: nil,
        gpsData: GPSData(latitude: 0, longitude: 0, speedOverGround: 99, courseOverGround: 0),
        gpsSignal: GPSSignalSnapshot(
            fixQuality: 1,
            fixMode: 3,
            selectionMode: "A",
            satellitesUsed: 0,
            hdop: 1,
            vdop: 1,
            pdop: 1,
            altitudeMeters: 0,
            geoidalSeparationMeters: 0,
            satellites: []
        ),
        turnRate: 0,
        logDistanceNm: 0,
        tripDistanceNm: 0,
        navigationTarget: nil
    )
}

private func sensorState() -> SimulationState {
    let simulator = sensorSimulator()
    var state = SimulationState(from: simulator)
    state.enableExperimentRandomness(seed: 8)
    state.hiddenPolarOverride = .beneteauFirst407
    return state
}

private func sensorConfig() -> SimulationConfig {
    let simulator = sensorSimulator()
    simulator.boatSpeedMode = .estimated
    return simulator.captureSimulationConfig()
}

private func sensorSimulator() -> NMEASimulator {
    let suite = "ExperimentSensor.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.weatherSourceMode = .manual
    simulator.boatProfile = .beneteauFirst407
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasGPS = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 6, courseOverGround: 90)
    return simulator
}
