import Foundation
import Testing
import XCTest
@testable import MarineSimulator

@Suite(.serialized)
@MainActor
struct ParametricPolarComparisonTests {

    @Test
    func extasyParametricPolarTracksFarrTableShapeAndHullSpeed() throws {
        let extasy = try #require(BuiltInVesselID.seeds.first(where: { $0.id == BuiltInVesselID.extasy }))
        let generator = try #require(ParametricPolarGenerator(vessel: extasy))

        let winds: [Double] = [6, 12, 20]
        let angles: [Double] = [36, 45, 60, 75, 90, 110, 135, 150, 170, 180]

        var lines: [String] = []
        lines.append(String(
            format: "Extasy Parametric Summary: LWL=%.2fm, V_hull=%.2fkn, SA_up=%.1fm2, SA_dn=%.1fm2, SA/D=%.1f, D/L=%.1f",
            generator.summary.waterlineLengthMeters,
            generator.summary.hullSpeedKnots,
            generator.summary.upwindSailAreaSquareMeters,
            generator.summary.downwindSailAreaSquareMeters,
            generator.summary.sailAreaToDisplacementRatio,
            generator.summary.displacementToLengthRatio
        ))

        var sqErrors: [Double] = []
        var upwindSqErrors: [Double] = []
        var reachSqErrors: [Double] = []
        var downwindSqErrors: [Double] = []

        for tws in winds {
            var rowParts: [String] = [String(format: "TWS %2.0f kn:", tws)]
            for twa in angles {
                let farr = BoatProfile.beneteauFirst407.estimatedBoatSpeed(
                    trueWindSpeedKnots: tws,
                    trueWindAngleDegrees: twa
                ) ?? 0
                let synth = generator.predictedSpeedKnots(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)
                let diff = synth - farr
                let sq = diff * diff
                sqErrors.append(sq)
                if twa <= 60 { upwindSqErrors.append(sq) }
                else if twa <= 110 { reachSqErrors.append(sq) }
                else { downwindSqErrors.append(sq) }

                rowParts.append(String(format: " %3.0f°:F=%.2f/S=%.2f(%+.2f)", twa, farr, synth, diff))
            }
            lines.append(rowParts.joined(separator: " |"))
        }

        let totalRMSE = sqrt(sqErrors.reduce(0, +) / Double(sqErrors.count))
        let upwindRMSE = sqrt(upwindSqErrors.reduce(0, +) / Double(upwindSqErrors.count))
        let reachRMSE = sqrt(reachSqErrors.reduce(0, +) / Double(reachSqErrors.count))
        let downwindRMSE = sqrt(downwindSqErrors.reduce(0, +) / Double(downwindSqErrors.count))

        lines.append(String(
            format: "Prior RMSE vs Farr #354 -> Total: %.3f kn | Upwind(<=60): %.3f kn | Reach(75-110): %.3f kn | Downwind(>=135): %.3f kn",
            totalRMSE, upwindRMSE, reachRMSE, downwindRMSE
        ))

        let report = lines.joined(separator: "\n")
        NSLog("%@", report)

        // Sanity bounds for a pure geometry-only VPP prior (zero access to Farr table)
        #expect(generator.summary.hullSpeedKnots > 7.5 && generator.summary.hullSpeedKnots < 8.5)
        #expect(totalRMSE < 1.2)
    }

    @Test
    func adaptiveRecoveryStartingFromSyntheticPriorConvergesTowardFarrPolar() throws {
        // Pretend Extasy has NO Farr table at all: the estimator starts from the
        // geometry-only ParametricPolarGenerator prior and adapts from CSV measurements.
        let extasy = try #require(BuiltInVesselID.seeds.first(where: { $0.id == BuiltInVesselID.extasy }))
        let prior = try #require(ParametricPolarGenerator(vessel: extasy))

        // Simulate 12 minutes of sailing on the true (un-degraded) Farr polar with realistic noise & course sweep.
        let session = ExperimentDiagnosticsSession()
        session.seed = 42
        session.windDirectionDegrees = 135
        session.windDirectionSwingDegrees = 15
        session.windSpeedKnots = 12
        session.windSpeedAmplitudeKnots = 4
        session.windPeriodSeconds = 120
        session.boatHeadingDegrees = 45
        session.courseSweepDegreesPerSecond = 0.5
        session.currentSetDegrees = 45
        session.currentDriftKnots = 1.2
        session.durationSeconds = 720
        session.hiddenPerformance = PerformanceParameters() // 1.0x Farr truth
        session.errors = SensorErrorConfiguration(
            apparentWindSpeed: .init(bias: 0, noiseAmplitude: 0.3),
            apparentWindAngle: .init(bias: 0, noiseAmplitude: 1.5),
            speedThroughWater: .init(bias: 0, noiseAmplitude: 0.15),
            trueHeading: .init(bias: 0, noiseAmplitude: 0.5),
            magneticCompass: .init(bias: 0, noiseAmplitude: 0.8)
        )

        session.prepare()
        session.start()
        let steps = Int((720.0 / ExperimentDiagnosticsSession.physicsInterval).rounded())
        for _ in 0..<steps {
            session.advance()
        }

        let csv = session.exportEstimatorCSV()
        let observations = parseObservations(csv)
        #expect(observations.count >= 700)

        // Adapt the synthetic prior using observed STW / prior(TWS, TWA) ratios per 15° TWA sector.
        var bucketRatios: [Int: [Double]] = [:]
        var allRatios: [Double] = []
        for i in observations.indices {
            let obs = observations[i]
            let twa = abs(calculateShortestRotation(from: obs.heading, to: obs.twd))
            guard twa >= 35, obs.tws >= 4, obs.stw > 0.5 else { continue }
            if i > 0, abs(obs.stw - observations[i - 1].stw) > 0.35 { continue }
            let base = prior.predictedSpeedKnots(trueWindSpeedKnots: obs.tws, trueWindAngleDegrees: twa)
            guard base > 1.0 else { continue }
            let ratio = obs.stw / base
            guard (0.4...2.0).contains(ratio) else { continue }
            allRatios.append(ratio)
            let bucket = Int((twa.clamped(to: 0...180) / 15.0).rounded()) * 15
            bucketRatios[bucket, default: []].append(ratio)
        }

        let globalRatio = median(allRatios) ?? 1.0
        var sectorFactors: [Int: Double] = [:]
        for (bucket, vals) in bucketRatios where vals.count >= 15 {
            if let m = median(vals) {
                let w = Double(vals.count) / Double(vals.count + 10)
                sectorFactors[bucket] = w * m + (1 - w) * globalRatio
            }
        }

        let evalTWS: [Double] = [8, 10, 12, 14, 16]
        let evalTWA: [Double] = [40, 50, 60, 75, 90, 110, 130, 145, 160, 175]
        var priorSq = 0.0
        var adaptedSq = 0.0
        var count = 0
        var sampleLines: [String] = []

        for tws in evalTWS {
            for twa in evalTWA {
                guard let farr = BoatProfile.beneteauFirst407.estimatedBoatSpeed(
                    trueWindSpeedKnots: tws,
                    trueWindAngleDegrees: twa
                ) else { continue }
                let synth = prior.predictedSpeedKnots(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)
                let bucket = Int((twa / 15.0).rounded()) * 15
                let factor = sectorFactors[bucket] ?? globalRatio
                let adapted = synth * factor

                priorSq += pow(synth - farr, 2)
                adaptedSq += pow(adapted - farr, 2)
                count += 1

                if tws == 12 {
                    sampleLines.append(String(
                        format: "TWS=12 TWA=%3.0f° -> Farr=%.2f | Synthetic=%.2f | Adapted=%.2f (factor=%.3f)",
                        twa, farr, synth, adapted, factor
                    ))
                }
            }
        }

        let priorRMSE = sqrt(priorSq / Double(count))
        let adaptedRMSE = sqrt(adaptedSq / Double(count))
        NSLog(
            "Cold-start Synthetic -> Adapted vs Farr RMSE: prior=%.3f kn -> adapted=%.3f kn\n%@",
            priorRMSE,
            adaptedRMSE,
            sampleLines.joined(separator: "\n")
        )

        #expect(adaptedRMSE < priorRMSE)
        #expect(adaptedRMSE < 0.55)
    }

    static func buildComparisonReport() throws -> String {
        let extasy = BuiltInVesselID.seeds.first(where: { $0.id == BuiltInVesselID.extasy })!
        let nimana = BuiltInVesselID.seeds.first(where: { $0.id == BuiltInVesselID.nimana })!
        let generator = ParametricPolarGenerator(vessel: extasy)!
        let nimanaGen = ParametricPolarGenerator(vessel: nimana)!

        let winds: [Double] = [6, 12, 20]
        let angles: [Double] = [36, 45, 60, 75, 90, 110, 135, 150, 170, 180]
        var out: [String] = []
        out.append(String(
            format: "Extasy Geometry: LWL=%.2fm, V_hull=%.2fkn, SA_up=%.1fm2, SA_dn=%.1fm2, SA/D=%.1f, D/L=%.1f",
            generator.summary.waterlineLengthMeters,
            generator.summary.hullSpeedKnots,
            generator.summary.upwindSailAreaSquareMeters,
            generator.summary.downwindSailAreaSquareMeters,
            generator.summary.sailAreaToDisplacementRatio,
            generator.summary.displacementToLengthRatio
        ))
        out.append(String(
            format: "Nimana Geometry: LWL=%.2fm, V_hull=%.2fkn, SA_up=%.1fm2, SA_dn=%.1fm2, SA/D=%.1f, D/L=%.1f",
            nimanaGen.summary.waterlineLengthMeters,
            nimanaGen.summary.hullSpeedKnots,
            nimanaGen.summary.upwindSailAreaSquareMeters,
            nimanaGen.summary.downwindSailAreaSquareMeters,
            nimanaGen.summary.sailAreaToDisplacementRatio,
            nimanaGen.summary.displacementToLengthRatio
        ))

        var sqErrors: [Double] = []
        var upwindSq: [Double] = []
        var reachSq: [Double] = []
        var downSq: [Double] = []
        for tws in winds {
            var parts: [String] = [String(format: "TWS=%2.0fkn:", tws)]
            for twa in angles {
                let farr = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa) ?? 0
                let synth = generator.predictedSpeedKnots(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)
                let nim = nimanaGen.predictedSpeedKnots(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)
                let diff = synth - farr
                let sq = diff * diff
                sqErrors.append(sq)
                if twa <= 60 { upwindSq.append(sq) }
                else if twa <= 110 { reachSq.append(sq) }
                else { downSq.append(sq) }
                parts.append(String(format: "%3.0f°:F=%.2f/S=%.2f(%+.2f)/N=%.2f", twa, farr, synth, diff, nim))
            }
            out.append(parts.joined(separator: " | "))
        }
        out.append(String(
            format: "Prior RMSE -> Total=%.3f | Upwind=%.3f | Reach=%.3f | Downwind=%.3f",
            sqrt(sqErrors.reduce(0, +) / Double(sqErrors.count)),
            sqrt(upwindSq.reduce(0, +) / Double(upwindSq.count)),
            sqrt(reachSq.reduce(0, +) / Double(reachSq.count)),
            sqrt(downSq.reduce(0, +) / Double(downSq.count))
        ))

        // Also run cold-start adaptation at TWS=12
        let session = ExperimentDiagnosticsSession()
        session.seed = 42
        session.windDirectionDegrees = 135
        session.windDirectionSwingDegrees = 15
        session.windSpeedKnots = 12
        session.windSpeedAmplitudeKnots = 4
        session.windPeriodSeconds = 120
        session.boatHeadingDegrees = 45
        session.courseSweepDegreesPerSecond = 0.5
        session.currentSetDegrees = 45
        session.currentDriftKnots = 1.2
        session.durationSeconds = 720
        session.hiddenPerformance = PerformanceParameters()
        session.errors = SensorErrorConfiguration(
            apparentWindSpeed: .init(bias: 0, noiseAmplitude: 0.3),
            apparentWindAngle: .init(bias: 0, noiseAmplitude: 1.5),
            speedThroughWater: .init(bias: 0, noiseAmplitude: 0.15),
            trueHeading: .init(bias: 0, noiseAmplitude: 0.5),
            magneticCompass: .init(bias: 0, noiseAmplitude: 0.8)
        )
        session.prepare()
        session.start()
        for _ in 0..<14_400 { session.advance() }

        let helper = ParametricPolarComparisonTests()
        let obs = helper.parseObservations(session.exportEstimatorCSV())
        var bucketRatios: [Int: [Double]] = [:]
        var allRatios: [Double] = []
        for i in obs.indices {
            let o = obs[i]
            let twa = abs(calculateShortestRotation(from: o.heading, to: o.twd))
            guard twa >= 35, o.tws >= 4, o.stw > 0.5 else { continue }
            if i > 0, abs(o.stw - obs[i - 1].stw) > 0.35 { continue }
            let base = generator.predictedSpeedKnots(trueWindSpeedKnots: o.tws, trueWindAngleDegrees: twa)
            guard base > 1.0 else { continue }
            let ratio = o.stw / base
            guard (0.4...2.0).contains(ratio) else { continue }
            allRatios.append(ratio)
            bucketRatios[Int((twa.clamped(to: 0...180) / 15.0).rounded()) * 15, default: []].append(ratio)
        }
        let global = helper.median(allRatios) ?? 1.0
        var sectors: [Int: Double] = [:]
        for (b, vals) in bucketRatios where vals.count >= 15 {
            if let m = helper.median(vals) {
                let w = Double(vals.count) / Double(vals.count + 10)
                sectors[b] = w * m + (1 - w) * global
            }
        }
        var priorSq = 0.0
        var adaptSq = 0.0
        var c = 0
        for tws in [8.0, 10.0, 12.0, 14.0, 16.0] {
            for twa in [40.0, 50.0, 60.0, 75.0, 90.0, 110.0, 130.0, 145.0, 160.0, 175.0] {
                let farr = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)!
                let synth = generator.predictedSpeedKnots(trueWindSpeedKnots: tws, trueWindAngleDegrees: twa)
                let f = sectors[Int((twa / 15.0).rounded()) * 15] ?? global
                let ad = synth * f
                priorSq += pow(synth - farr, 2)
                adaptSq += pow(ad - farr, 2)
                c += 1
                if tws == 12 {
                    out.append(String(format: "TWS12 TWA=%3.0f°: Farr=%.2f | Synth=%.2f | Adapted=%.2f (k=%.3f)", twa, farr, synth, ad, f))
                }
            }
        }
        out.append(String(format: "Cold-start Adaptation RMSE: Prior=%.3f -> Adapted=%.3f kn", sqrt(priorSq / Double(c)), sqrt(adaptSq / Double(c))))
        return out.joined(separator: "\n")
    }

    private struct Obs {
        var twd: Double
        var tws: Double
        var heading: Double
        var stw: Double
    }

    private func parseObservations(_ csv: String) -> [Obs] {
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first?.split(separator: ",").map(String.init),
              let twdIdx = header.firstIndex(of: "trueWindDirection"),
              let twsIdx = header.firstIndex(of: "trueWindSpeed"),
              let hdgIdx = header.firstIndex(of: "trueHeading"),
              let stwIdx = header.firstIndex(of: "speedThroughWater") else { return [] }

        return lines.dropFirst().compactMap { line in
            let cols = line.split(separator: ",").map(String.init)
            guard cols.count == header.count,
                  let twd = Double(cols[twdIdx]),
                  let tws = Double(cols[twsIdx]),
                  let hdg = Double(cols[hdgIdx]),
                  let stw = Double(cols[stwIdx]) else { return nil }
            return Obs(twd: twd, tws: tws, heading: hdg, stw: stw)
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? 0.5 * (s[mid - 1] + s[mid]) : s[mid]
    }
}

@MainActor
final class ParametricPolarReportCase: XCTestCase {
    func testAttachComparisonReport() throws {
        let report = try ParametricPolarComparisonTests.buildComparisonReport()
        let attachment = XCTAttachment(string: report)
        attachment.name = "ComparisonReport.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
