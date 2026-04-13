import Foundation

enum BoatSpeedMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case estimated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .estimated:
            return "From Wind"
        }
    }
}

enum BoatProfile: String, Codable, CaseIterable, Identifiable {
    case beneteauFirst407
    case j109
    case hanse458

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beneteauFirst407:
            return "Beneteau First 40.7"
        case .j109:
            return "J/109"
        case .hanse458:
            return "Hanse 458"
        }
    }

    var shortName: String {
        switch self {
        case .beneteauFirst407:
            return "First 40.7"
        case .j109:
            return "J/109"
        case .hanse458:
            return "Hanse 458"
        }
    }

    var summary: String {
        switch self {
        case .beneteauFirst407:
            return "Polar boat speeds from Farr Yacht Design VPP (Beneteau First 40.7 racing, rough water, masthead TWS)."
        case .j109:
            return "Lighter sport-cruiser bias with sharper reaching performance."
        case .hanse458:
            return "Heavier cruising profile with steadier, lower top-end pace."
        }
    }

    func estimatedBoatSpeed(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> Double {
        polarTable.interpolatedSpeed(
            trueWindSpeedKnots: trueWindSpeedKnots,
            trueWindAngleDegrees: trueWindAngleDegrees
        )
    }

    private var polarTable: PolarTable {
        switch self {
        case .beneteauFirst407:
            // Farr Yacht Design VPP “Best Boatspeeds (kt)”, Design #354, racing sail plan, rough water; TWA × TWS @ masthead.
            return .init(
                windSpeeds: [4, 6, 8, 10, 12, 14, 16, 20, 25, 30],
                angles: [33, 36, 39, 42, 45, 50, 60, 70, 80, 90, 100, 110, 120, 130, 135, 140, 150, 160, 170, 180],
                speeds: [
                    [2.37, 2.69, 2.97, 3.23, 3.46, 3.79, 4.29, 4.59, 4.72, 4.70, 4.51, 4.36, 4.15, 3.76, 3.53, 3.30, 2.83, 2.40, 2.17, 2.02],
                    [3.57, 3.99, 4.36, 4.68, 4.97, 5.37, 5.92, 6.23, 6.36, 6.34, 6.17, 6.13, 5.88, 5.43, 5.16, 4.86, 4.25, 3.64, 3.28, 3.06],
                    [4.50, 4.98, 5.40, 5.75, 6.05, 6.44, 6.92, 7.15, 7.24, 7.23, 7.27, 7.21, 7.02, 6.69, 6.46, 6.18, 5.52, 4.80, 4.36, 4.08],
                    [5.17, 5.68, 6.08, 6.42, 6.69, 7.03, 7.43, 7.65, 7.75, 7.78, 7.86, 7.82, 7.67, 7.44, 7.29, 7.10, 6.56, 5.85, 5.38, 5.05],
                    [5.62, 6.10, 6.48, 6.78, 7.01, 7.29, 7.69, 7.98, 8.14, 8.18, 8.24, 8.29, 8.19, 7.99, 7.85, 7.69, 7.28, 6.74, 6.29, 5.95],
                    [5.90, 6.35, 6.71, 6.98, 7.18, 7.44, 7.84, 8.16, 8.42, 8.53, 8.48, 8.63, 8.63, 8.46, 8.33, 8.18, 7.79, 7.36, 7.02, 6.72],
                    [6.05, 6.50, 6.84, 7.09, 7.28, 7.53, 7.95, 8.29, 8.58, 8.81, 8.83, 8.87, 9.03, 8.91, 8.77, 8.61, 8.23, 7.85, 7.55, 7.30],
                    [6.08, 6.55, 6.90, 7.16, 7.36, 7.64, 8.10, 8.47, 8.81, 9.17, 9.45, 9.42, 9.63, 9.84, 9.74, 9.54, 9.06, 8.67, 8.39, 8.16],
                    [5.74, 6.34, 6.79, 7.11, 7.35, 7.67, 8.19, 8.62, 9.04, 9.48, 9.89, 10.28, 10.26, 10.97, 11.21, 11.10, 10.35, 9.78, 9.40, 9.09],
                    [4.67, 5.78, 6.41, 6.88, 7.21, 7.60, 8.20, 8.68, 9.18, 9.70, 10.23, 10.87, 11.42, 11.98, 12.59, 13.01, 12.32, 11.39, 10.72, 10.19]
                ]
            )
        case .j109:
            return .init(
                windSpeeds: [6, 8, 10, 12, 16, 20],
                angles: [35, 45, 60, 75, 90, 110, 135, 150, 165],
                speeds: [
                    [4.0, 4.9, 5.5, 5.8, 5.7, 5.5, 5.1, 4.5, 3.9],
                    [4.9, 5.8, 6.6, 7.0, 7.1, 6.8, 6.3, 5.6, 4.9],
                    [5.4, 6.4, 7.4, 8.0, 8.2, 8.0, 7.5, 6.7, 5.6],
                    [5.8, 6.9, 8.0, 8.7, 9.0, 8.9, 8.3, 7.5, 6.1],
                    [6.1, 7.3, 8.4, 9.2, 9.6, 9.8, 9.2, 8.2, 6.8],
                    [6.2, 7.5, 8.7, 9.5, 9.9, 10.2, 9.6, 8.6, 7.1]
                ]
            )
        case .hanse458:
            return .init(
                windSpeeds: [6, 8, 10, 12, 16, 20],
                angles: [35, 45, 60, 75, 90, 110, 135, 150, 165],
                speeds: [
                    [3.7, 4.4, 4.9, 5.2, 5.3, 5.1, 4.8, 4.3, 3.8],
                    [4.4, 5.1, 5.8, 6.2, 6.3, 6.1, 5.8, 5.2, 4.6],
                    [4.8, 5.6, 6.4, 6.9, 7.1, 7.0, 6.7, 6.0, 5.1],
                    [5.1, 6.0, 6.8, 7.4, 7.6, 7.6, 7.2, 6.5, 5.5],
                    [5.4, 6.3, 7.3, 8.0, 8.3, 8.4, 8.0, 7.1, 6.0],
                    [5.5, 6.5, 7.5, 8.2, 8.6, 8.8, 8.3, 7.4, 6.2]
                ]
            )
        }
    }
}

private struct PolarTable {
    let windSpeeds: [Double]
    let angles: [Double]
    let speeds: [[Double]]

    func interpolatedSpeed(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> Double {
        let clampedWind = trueWindSpeedKnots.clamped(to: windSpeeds.first!...windSpeeds.last!)
        let normalizedAngle = abs(trueWindAngleDegrees.truncatingRemainder(dividingBy: 360))
        let mirroredAngle = normalizedAngle > 180 ? 360 - normalizedAngle : normalizedAngle
        let minPolarAngle = angles.first!
        let clampedAngle = mirroredAngle.clamped(to: minPolarAngle...angles.last!)

        let windIndex = lowerIndex(for: clampedWind, in: windSpeeds)
        let angleIndex = lowerIndex(for: clampedAngle, in: angles)

        let nextWindIndex = min(windIndex + 1, windSpeeds.count - 1)
        let nextAngleIndex = min(angleIndex + 1, angles.count - 1)

        let wind0 = windSpeeds[windIndex]
        let wind1 = windSpeeds[nextWindIndex]
        let angle0 = angles[angleIndex]
        let angle1 = angles[nextAngleIndex]

        let q11 = speeds[windIndex][angleIndex]
        let q12 = speeds[windIndex][nextAngleIndex]
        let q21 = speeds[nextWindIndex][angleIndex]
        let q22 = speeds[nextWindIndex][nextAngleIndex]

        let windFraction = fraction(of: clampedWind, lower: wind0, upper: wind1)
        let angleFraction = fraction(of: clampedAngle, lower: angle0, upper: angle1)

        let lowerBlend = q11 + (q12 - q11) * angleFraction
        let upperBlend = q21 + (q22 - q21) * angleFraction
        let interpolated = lowerBlend + (upperBlend - lowerBlend) * windFraction

        // Polars start at the tightest tabulated upwind angle (e.g. 33°). That speed assumes you are
        // trimmed and footing at that angle — not pinching with the bow into the wind at 3–15° TWA.
        // Scale down smoothly toward 0° so “into the wind” is not rewarded with close-hauled polar boat speed.
        if mirroredAngle < minPolarAngle {
            let ratio = mirroredAngle / minPolarAngle
            let pinchingFactor = ratio * ratio
            return max(0, interpolated * pinchingFactor)
        }

        return max(0, interpolated)
    }

    private func lowerIndex(for value: Double, in values: [Double]) -> Int {
        guard let firstHigher = values.firstIndex(where: { $0 >= value }) else {
            return max(0, values.count - 2)
        }

        return max(0, min(firstHigher == 0 ? 0 : firstHigher - 1, values.count - 2))
    }

    private func fraction(of value: Double, lower: Double, upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return (value - lower) / (upper - lower)
    }
}
