import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
@MainActor
struct PolarRecoveryProofOfConceptTests {

    @Test
    func estimatorCSVEnforcesOutputContractAndExcludesTruth() {
        let session = ExperimentDiagnosticsSession()
        session.windDirectionDegrees = 135
        session.windSpeedKnots = 12
        session.boatHeadingDegrees = 90
        session.hiddenPerformance.hullFactor = 0.85
        session.durationSeconds = 5
        session.prepare()
        session.start()

        for _ in 0..<60 {
            session.advance()
        }

        let csv = session.exportEstimatorCSV()
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 5) // header + t=0.05, 1.05, 2.05, 3.05
        #expect(lines.first == "timestamp,trueWindDirection,trueWindSpeed,trueHeading,speedThroughWater")
        #expect(csv.contains("hullFactor") == false)
        #expect(csv.contains("0.85") == false)
        #expect(csv.contains("truth") == false)

        let truthCSV = session.exportEvaluationTruthCSV()
        #expect(truthCSV.contains("truthSpeedThroughWater"))
        #expect(session.recordedSampleCount >= 3)

        session.reset()
        #expect(session.recordedSampleCount == 0)
    }

    @Test
    func offlineEstimatorRecoversHiddenDegradedPolarFromEstimatorCSVAlone() throws {
        // 1. Run an isolated experiment with hidden degradation, first-order speed lag,
        //    time-varying wind, 360° course sweep, current drift, and zero-mean sensor noise.
        let hidden = PerformanceParameters(
            speedResponse: .firstOrder,
            hullFactor: 0.85,
            sailFactor: 0.92,
            trimEfficiency: 0.96,
            seaStateFactor: 1.0,
            accelerationTimeConstantSeconds: 5,
            decelerationTimeConstantSeconds: 8
        )
        let trueCombinedFactor = hidden.hullFactor * hidden.sailFactor * hidden.trimEfficiency * hidden.seaStateFactor
        // 0.85 * 0.92 * 0.96 = 0.75072

        let session = ExperimentDiagnosticsSession()
        session.seed = 42
        session.windDirectionDegrees = 135
        session.windDirectionSwingDegrees = 20
        session.windSpeedKnots = 12
        session.windSpeedAmplitudeKnots = 3
        session.windPeriodSeconds = 120
        session.boatHeadingDegrees = 45
        session.courseSweepDegreesPerSecond = 0.5
        session.currentSetDegrees = 45
        session.currentDriftKnots = 1.5
        session.durationSeconds = 720
        session.hiddenPerformance = hidden
        session.errors = SensorErrorConfiguration(
            apparentWindSpeed: SensorChannelError(bias: 0, noiseAmplitude: 0.4),
            apparentWindAngle: SensorChannelError(bias: 0, noiseAmplitude: 1.5),
            speedThroughWater: SensorChannelError(bias: 0, noiseAmplitude: 0.15),
            trueHeading: SensorChannelError(bias: 0, noiseAmplitude: 0.5),
            magneticCompass: SensorChannelError(bias: 0, noiseAmplitude: 0.8)
        )

        session.prepare()
        session.start()
        let totalSteps = Int((720.0 / ExperimentDiagnosticsSession.physicsInterval).rounded())
        for _ in 0..<totalSteps {
            session.advance()
        }

        // 2. Export ONLY the estimator-permitted CSV (no truth columns, no hidden factors).
        let estimatorCSV = session.exportEstimatorCSV()
        #expect(estimatorCSV.contains("truth") == false)

        // 3. Parse only the CSV and fit an adapted polar multiplier against BoatProfile.beneteauFirst407.
        let observations = try parseEstimatorCSV(estimatorCSV)
        #expect(observations.count >= 700)

        let fit = PrototypePolarAdapter.fit(
            observations: observations,
            referenceProfile: .beneteauFirst407
        )
        #expect(fit.acceptedSampleCount >= 400)
        #expect(abs(fit.globalFactor - trueCombinedFactor) < 0.02)

        // 4. Evaluate polar prediction RMSE across a full TWS x TWA grid against the hidden true polar.
        let gridTWS = [6.0, 8.0, 10.0, 12.0, 14.0, 16.0]
        let gridTWA = [40.0, 60.0, 80.0, 100.0, 120.0, 140.0, 160.0]

        var baselineSqError = 0.0
        var adaptedSqError = 0.0
        var cellCount = 0

        for tws in gridTWS {
            for twa in gridTWA {
                guard let refSpeed = BoatProfile.beneteauFirst407.estimatedBoatSpeed(
                    trueWindSpeedKnots: tws,
                    trueWindAngleDegrees: twa
                ) else { continue }
                let trueHiddenSpeed = refSpeed * trueCombinedFactor
                let adaptedSpeed = fit.predictSpeed(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)
                baselineSqError += pow(refSpeed - trueHiddenSpeed, 2)
                adaptedSqError += pow(adaptedSpeed - trueHiddenSpeed, 2)
                cellCount += 1
            }
        }

        let baselineRMSE = sqrt(baselineSqError / Double(cellCount))
        let adaptedRMSE = sqrt(adaptedSqError / Double(cellCount))

        print(
            """
            [PoC Polar Recovery] samples=\(observations.count), accepted=\(fit.acceptedSampleCount), \
            trueFactor=\(String(format: "%.4f", trueCombinedFactor)), \
            recoveredFactor=\(String(format: "%.4f", fit.globalFactor)), \
            baselineRMSE=\(String(format: "%.3f", baselineRMSE)) kn, \
            adaptedRMSE=\(String(format: "%.3f", adaptedRMSE)) kn
            """
        )

        #expect(baselineRMSE > 1.5)
        #expect(adaptedRMSE < 0.15)
        #expect(adaptedRMSE < baselineRMSE * 0.08)
    }

    @Test
    func uncalibratedSpeedLogBiasLimitsPolarRecoveryAccuracy() throws {
        // Demonstrates why sensor bias calibration matters in the thesis methodology:
        // a +0.60 kn STW bias shifts the recovered polar systematically upward.
        let hidden = PerformanceParameters(
            speedResponse: .instant,
            hullFactor: 0.80,
            sailFactor: 1.0,
            trimEfficiency: 1.0,
            seaStateFactor: 1.0
        )

        let session = ExperimentDiagnosticsSession()
        session.seed = 7
        session.windDirectionDegrees = 135
        session.windSpeedKnots = 12
        session.boatHeadingDegrees = 45
        session.courseSweepDegreesPerSecond = 1.0
        session.durationSeconds = 360
        session.hiddenPerformance = hidden
        session.errors = SensorErrorConfiguration(
            apparentWindSpeed: .init(bias: 0, noiseAmplitude: 0.2),
            apparentWindAngle: .init(bias: 0, noiseAmplitude: 1.0),
            speedThroughWater: .init(bias: 0.60, noiseAmplitude: 0.1),
            trueHeading: .init(bias: 0, noiseAmplitude: 0.5),
            magneticCompass: .init(bias: 0, noiseAmplitude: 0.5)
        )

        session.prepare()
        session.start()
        let totalSteps = Int((360.0 / ExperimentDiagnosticsSession.physicsInterval).rounded())
        for _ in 0..<totalSteps {
            session.advance()
        }

        let observations = try parseEstimatorCSV(session.exportEstimatorCSV())
        let fit = PrototypePolarAdapter.fit(
            observations: observations,
            referenceProfile: .beneteauFirst407
        )

        // Recovered factor is pushed upward (~0.88 vs true 0.80) by the +0.60 kn STW bias.
        #expect(fit.globalFactor > 0.85)
        #expect(fit.globalFactor < 0.93)
    }

    // MARK: - Prototype Offline Estimator (reads CSV only)

    private struct EstimatorObservation {
        var twd: Double
        var tws: Double
        var heading: Double
        var stw: Double
    }

    private struct PrototypePolarAdapter {
        var referenceProfile: BoatProfile
        var globalFactor: Double
        var angleBucketFactors: [Int: Double] // 15-degree |TWA| bucket -> median ratio
        var acceptedSampleCount: Int

        func predictSpeed(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> Double {
            guard let ref = referenceProfile.estimatedBoatSpeed(
                trueWindSpeedKnots: trueWindSpeedKnots,
                trueWindAngleDegrees: trueWindAngleDegrees
            ) else { return 0 }
            let bucket = Self.angleBucket(for: trueWindAngleDegrees)
            let factor = angleBucketFactors[bucket] ?? globalFactor
            return ref * factor
        }

        static func fit(
            observations: [EstimatorObservation],
            referenceProfile: BoatProfile
        ) -> PrototypePolarAdapter {
            var allRatios: [Double] = []
            var bucketRatios: [Int: [Double]] = [:]

            for index in observations.indices {
                let sample = observations[index]
                let twa = abs(calculateShortestRotation(from: sample.heading, to: sample.twd))
                guard twa >= 35, sample.tws >= 4, sample.stw > 0.5 else { continue }

                // Simple steadiness filter: skip transient lag points where speed changed sharply.
                if index > 0 {
                    let prev = observations[index - 1]
                    if abs(sample.stw - prev.stw) > 0.35 { continue }
                }

                guard let refSpeed = referenceProfile.estimatedBoatSpeed(
                    trueWindSpeedKnots: sample.tws,
                    trueWindAngleDegrees: twa
                ), refSpeed > 1.0 else { continue }

                let ratio = sample.stw / refSpeed
                guard (0.2...2.0).contains(ratio) else { continue }
                allRatios.append(ratio)
                bucketRatios[angleBucket(for: twa), default: []].append(ratio)
            }

            let global = median(allRatios) ?? 1.0
            var resolvedBuckets: [Int: Double] = [:]
            for (bucket, ratios) in bucketRatios where ratios.count >= 25 {
                if let m = median(ratios) {
                    let weight = Double(ratios.count) / Double(ratios.count + 20)
                    resolvedBuckets[bucket] = weight * m + (1 - weight) * global
                }
            }

            return PrototypePolarAdapter(
                referenceProfile: referenceProfile,
                globalFactor: global,
                angleBucketFactors: resolvedBuckets,
                acceptedSampleCount: allRatios.count
            )
        }

        private static func angleBucket(for twa: Double) -> Int {
            let clamped = abs(twa).clamped(to: 0...180)
            return Int((clamped / 15.0).rounded()) * 15
        }

        private static func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            if sorted.count.isMultiple(of: 2) {
                return 0.5 * (sorted[mid - 1] + sorted[mid])
            }
            return sorted[mid]
        }
    }

    private func parseEstimatorCSV(_ csv: String) throws -> [EstimatorObservation] {
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        guard let headerLine = lines.first else { return [] }
        let headers = headerLine.split(separator: ",").map(String.init)
        let twdIndex = try #require(headers.firstIndex(of: "trueWindDirection"))
        let twsIndex = try #require(headers.firstIndex(of: "trueWindSpeed"))
        let hdgIndex = try #require(headers.firstIndex(of: "trueHeading"))
        let stwIndex = try #require(headers.firstIndex(of: "speedThroughWater"))

        var result: [EstimatorObservation] = []
        for line in lines.dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count == headers.count,
                  let twd = Double(cols[twdIndex]),
                  let tws = Double(cols[twsIndex]),
                  let hdg = Double(cols[hdgIndex]),
                  let stw = Double(cols[stwIndex]) else {
                continue
            }
            result.append(EstimatorObservation(twd: twd, tws: tws, heading: hdg, stw: stw))
        }
        return result
    }
}
