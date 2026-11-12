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
    case nimana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beneteauFirst407:
            return "Extasy — Beneteau First 40.7 (1999)"
        case .nimana:
            return "Nimana — Bavaria Cruiser 46 (2015)"
        }
    }

    var shortName: String {
        switch self {
        case .beneteauFirst407:
            return "Extasy"
        case .nimana:
            return "Nimana"
        }
    }

    var summary: String {
        switch self {
        case .beneteauFirst407:
            return "Beneteau First 40.7 (1999). Speed grid and optima from the Farr Design #354 manufacturer prediction."
        case .nimana:
            return "Bavaria Cruiser 46 (2015). Polar is pending integration. From Wind holds the current boat speed."
        }
    }

    var hasSpeedPolar: Bool {
        self == .beneteauFirst407
    }

    var sailingProfile: SailingProfile {
        switch self {
        case .beneteauFirst407:
            return .extasy
        case .nimana:
            return .nimana
        }
    }

    /// Nil when this boat has no speed polar. Nimana does not invent one.
    func estimatedBoatSpeed(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> Double? {
        polarTable?.interpolatedSpeed(
            trueWindSpeedKnots: trueWindSpeedKnots,
            trueWindAngleDegrees: trueWindAngleDegrees
        )
    }

    /// True wind angle (degrees) used for close-hauled tack targets — interpolated vs true wind speed where a table exists.
    func optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: Double) -> Double {
        let tws = trueWindSpeedKnots.clamped(to: 0.5...60)
        switch self {
        case .beneteauFirst407:
            if let angle = SailingProfile.extasy.optimalUpwindTrueWindAngle(trueWindSpeedKnots: tws) {
                return angle
            }
            return Self.interpolateAngleTable(
                SailingProfile.farrUpwindOptima.map { (tw: $0.wind, angle: $0.angle) },
                windSpeedKnots: tws
            )
        case .nimana:
            return 0
        }
    }

    private var polarTable: PolarTable? {
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
        case .nimana:
            return nil
        }
    }

    private static func interpolateAngleTable(_ samples: [(tw: Double, angle: Double)], windSpeedKnots: Double) -> Double {
        guard let first = samples.first else { return 40 }
        guard samples.count > 1 else { return first.angle }
        let tws = windSpeedKnots.clamped(to: first.tw...samples.last!.tw)
        guard let upperIndex = samples.firstIndex(where: { $0.tw >= tws }) else {
            return samples.last!.angle
        }
        if upperIndex == 0 {
            return samples[0].angle
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        guard upper.tw > lower.tw else { return upper.angle }
        let t = (tws - lower.tw) / (upper.tw - lower.tw)
        return lower.angle + (upper.angle - lower.angle) * t
    }
}

/// Lookup used by both the reference polar and the hidden polar.
/// Interpolation stays on `BoatProfile` so the First 40.7 table is unchanged.
struct PolarModel: Equatable, Sendable {
    var profile: BoatProfile

    func targetSpeedKnots(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> Double? {
        profile.estimatedBoatSpeed(
            trueWindSpeedKnots: trueWindSpeedKnots,
            trueWindAngleDegrees: trueWindAngleDegrees
        )
    }

    func optimalUpwindAngleDegrees(trueWindSpeedKnots: Double) -> Double {
        profile.optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: trueWindSpeedKnots)
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

// MARK: - Polar provenance

/// Where a polar dataset came from. ORC and Adapted exist so later datasets stay distinct.
/// This milestone does not create ORC or Adapted records and does not compare or adapt polars.
enum PolarProvenanceKind: String, Equatable, Sendable {
    case manufacturer
    case orc
    case adapted
}

struct PolarProvenance: Equatable, Sendable {
    var kind: PolarProvenanceKind
    var boatIdentifier: String
    var reference: String
    var version: String?
}

/// One identifiable polar dataset. Comparison and adaptation are later milestones.
struct PolarDatasetIdentity: Equatable, Sendable {
    var provenance: PolarProvenance
}

// MARK: - Sailing state

enum PointOfSail: String, Equatable, Sendable {
    case noGo
    case closeHauled
    case closeReach
    case beamReach
    case broadReach
    case running

    var displayName: String {
        switch self {
        case .noGo: return "No-go"
        case .closeHauled: return "Close-hauled"
        case .closeReach: return "Close reach"
        case .beamReach: return "Beam reach"
        case .broadReach: return "Broad reach"
        case .running: return "Running"
        }
    }
}

/// Absolute true-wind-angle bands. These are simulator settings, not Farr values.
struct SailingStateBounds: Equatable, Sendable {
    var noGoEndsAt: Double = 30
    var closeHauledEndsAt: Double = 60
    var closeReachEndsAt: Double = 80
    var beamReachEndsAt: Double = 100
    var broadReachEndsAt: Double = 150

    func pointOfSail(absoluteTrueWindAngle angle: Double) -> PointOfSail {
        let twa = min(180, max(0, angle))
        if twa < noGoEndsAt { return .noGo }
        if twa < closeHauledEndsAt { return .closeHauled }
        if twa < closeReachEndsAt { return .closeReach }
        if twa < beamReachEndsAt { return .beamReach }
        if twa < broadReachEndsAt { return .broadReach }
        return .running
    }
}

/// Which automatic maneuvers are normal in each point of sail. Not a claim of physical impossibility.
struct ManeuverEligibilityPolicy: Equatable, Sendable {
    var tackPoints: Set<PointOfSail>
    var gybePoints: Set<PointOfSail>

    static let simulatorDefault = ManeuverEligibilityPolicy(
        tackPoints: [.closeHauled, .closeReach, .beamReach],
        gybePoints: [.closeReach, .beamReach, .broadReach, .running]
    )

    func allows(_ kind: ManeuverKind, at point: PointOfSail) -> Bool {
        switch kind {
        case .tack: return tackPoints.contains(point)
        case .gybe: return gybePoints.contains(point)
        }
    }

    func reason(for kind: ManeuverKind, at point: PointOfSail) -> String {
        switch point {
        case .noGo:
            return "No-go. Neither tack nor gybe is the normal maneuver."
        case .closeHauled:
            return "Close-hauled. Tack is the normal maneuver."
        case .broadReach:
            return "Broad reach. Gybe is the normal maneuver."
        case .running:
            return "Running. Gybe is the normal maneuver."
        case .closeReach, .beamReach:
            return kind == .tack
                ? "\(point.displayName). Tack is available."
                : "\(point.displayName). Gybe is available."
        }
    }
}

/// Farr `Sail` column. Independent of point of sail and of port/starboard tack.
enum TheoreticalSailCombination: String, Equatable, Sendable {
    case up = "Up"
    case down = "Dn"
}

struct ResolvedSailingState: Equatable, Sendable {
    var pointOfSail: PointOfSail
    var tack: ManeuverSide?
    var absoluteTrueWindAngle: Double
    var sailCombination: TheoreticalSailCombination?
    /// Point-of-sail bands are simulator-defined even when a manufacturer sail column is present.
    var pointOfSailIsSimulatorDefined = true
}

struct SailingProfile: Sendable {
    var identifier: String
    var name: String
    var bounds: SailingStateBounds
    var eligibility: ManeuverEligibilityPolicy
    /// Sourced datasets only. Empty means provenance is unavailable.
    var datasets: [PolarDatasetIdentity]
    var upwindOptima: [(wind: Double, angle: Double)]
    var downwindOptima: [(wind: Double, angle: Double)]
    /// Last tabulated Up angle and first tabulated Dn angle at each true wind speed.
    var sailBrackets: [(wind: Double, lastUp: Double, firstDown: Double)]

    static let extasy = SailingProfile(
        identifier: "extasy",
        name: "Extasy",
        bounds: SailingStateBounds(),
        eligibility: .simulatorDefault,
        datasets: [
            PolarDatasetIdentity(provenance: PolarProvenance(
                kind: .manufacturer,
                boatIdentifier: "extasy",
                reference: "Farr Yacht Design Performance Prediction, Design #354, Racing Version, for Chantiers Beneteau, 3 May 2001",
                version: "VPP 2.87, rough water, masthead wind, 354OWNRC.VPP"
            ))
        ],
        upwindOptima: farrUpwindOptima,
        downwindOptima: farrDownwindOptima,
        sailBrackets: farrSailBrackets
    )

    static let nimana = SailingProfile(
        identifier: "nimana",
        name: "Nimana",
        bounds: SailingStateBounds(),
        eligibility: .simulatorDefault,
        datasets: [],
        upwindOptima: [],
        downwindOptima: [],
        sailBrackets: []
    )

    /// Farr Design #354 `Up.Bt`, manufacturer-predicted. Not extrapolated outside 4…30 kn.
    static let farrUpwindOptima: [(wind: Double, angle: Double)] = [
        (4, 46.8), (6, 45.2), (8, 43.3), (10, 41.7), (12, 40.4),
        (14, 39.4), (16, 38.8), (20, 39.0), (25, 40.5), (30, 42.9)
    ]

    /// Farr Design #354 `Dn.Bt`, manufacturer-predicted. Not extrapolated outside 4…30 kn.
    static let farrDownwindOptima: [(wind: Double, angle: Double)] = [
        (4, 140.7), (6, 143.2), (8, 146.3), (10, 149.9), (12, 155.4),
        (14, 164.8), (16, 168.3), (20, 170.5), (25, 168.3), (30, 157.3)
    ]

    /// Best Performance `Sail` column. The gap between Up and Dn is not a point-of-sail boundary.
    static let farrSailBrackets: [(wind: Double, lastUp: Double, firstDown: Double)] = [
        (4, 100, 110), (6, 90, 100), (8, 90, 100), (10, 80, 90), (12, 90, 100),
        (14, 100, 110), (16, 100, 110), (20, 110, 120), (25, 110, 120), (30, 120, 130)
    ]

    func optimalUpwindTrueWindAngle(trueWindSpeedKnots: Double) -> Double? {
        interpolatedAngle(upwindOptima, windSpeedKnots: trueWindSpeedKnots)
    }

    func optimalDownwindTrueWindAngle(trueWindSpeedKnots: Double) -> Double? {
        interpolatedAngle(downwindOptima, windSpeedKnots: trueWindSpeedKnots)
    }

    /// Nil when neither wind-speed bracket establishes the same sail combination.
    func sailCombination(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> TheoreticalSailCombination? {
        guard !sailBrackets.isEmpty, trueWindSpeedKnots.isFinite, trueWindAngleDegrees.isFinite else { return nil }
        let angle = Self.absoluteAngle(trueWindAngleDegrees)
        guard angle >= 33, angle <= 180 else { return nil }
        let samples = sailBrackets
        guard let first = samples.first, let last = samples.last,
              trueWindSpeedKnots >= first.wind, trueWindSpeedKnots <= last.wind else { return nil }
        if let exact = samples.first(where: { $0.wind == trueWindSpeedKnots }) {
            return Self.sail(at: angle, bracket: exact)
        }
        guard let upperIndex = samples.firstIndex(where: { $0.wind >= trueWindSpeedKnots }), upperIndex > 0 else {
            return nil
        }
        let lower = Self.sail(at: angle, bracket: samples[upperIndex - 1])
        let upper = Self.sail(at: angle, bracket: samples[upperIndex])
        guard let lower, lower == upper else { return nil }
        return lower
    }

    func resolve(trueHeading: Double, trueWindDirection: Double, trueWindSpeedKnots: Double) -> ResolvedSailingState {
        let absolute = abs(calculateShortestRotation(from: trueHeading, to: normalizeAngle(trueWindDirection)))
        return ResolvedSailingState(
            pointOfSail: bounds.pointOfSail(absoluteTrueWindAngle: absolute),
            tack: SimulationEngine.currentTack(trueHeading: trueHeading, trueWindDirection: trueWindDirection),
            absoluteTrueWindAngle: absolute,
            sailCombination: sailCombination(trueWindSpeedKnots: trueWindSpeedKnots, trueWindAngleDegrees: absolute)
        )
    }

    /// Nil when the command may start. Does not change heading.
    func rejectionReason(
        for command: ManeuverCommand,
        trueHeading: Double,
        trueWindDirection: Double,
        trueWindSpeedKnots: Double
    ) -> String? {
        let state = resolve(
            trueHeading: trueHeading,
            trueWindDirection: trueWindDirection,
            trueWindSpeedKnots: trueWindSpeedKnots
        )
        if !eligibility.allows(command.kind, at: state.pointOfSail) {
            return eligibility.reason(for: command.kind, at: state.pointOfSail)
        }
        if SimulationEngine.maneuverPlan(
            command: command,
            fromHeading: trueHeading,
            trueWindDirection: trueWindDirection
        ) != nil {
            return nil
        }
        if state.tack == nil {
            return state.absoluteTrueWindAngle <= 90
                ? "Head to wind. The tack is ambiguous."
                : "Dead downwind. The tack is ambiguous."
        }
        if state.tack == command.side {
            let name = state.tack == .port ? "port" : "starboard"
            return "Already on \(name) tack."
        }
        return "The turn is too small."
    }

    func standingPolicyText(at point: PointOfSail) -> String? {
        let tack = eligibility.allows(.tack, at: point)
        let gybe = eligibility.allows(.gybe, at: point)
        if tack && gybe { return nil }
        return eligibility.reason(for: tack ? .gybe : .tack, at: point)
    }

    private func interpolatedAngle(_ samples: [(wind: Double, angle: Double)], windSpeedKnots: Double) -> Double? {
        guard windSpeedKnots.isFinite, let first = samples.first, let last = samples.last,
              windSpeedKnots >= first.wind, windSpeedKnots <= last.wind else { return nil }
        if let exact = samples.first(where: { $0.wind == windSpeedKnots }) { return exact.angle }
        guard let upperIndex = samples.firstIndex(where: { $0.wind >= windSpeedKnots }), upperIndex > 0 else {
            return nil
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        guard upper.wind > lower.wind else { return upper.angle }
        let fraction = (windSpeedKnots - lower.wind) / (upper.wind - lower.wind)
        return lower.angle + (upper.angle - lower.angle) * fraction
    }

    private static func absoluteAngle(_ angle: Double) -> Double {
        let normalized = abs(angle.truncatingRemainder(dividingBy: 360))
        return normalized > 180 ? 360 - normalized : normalized
    }

    private static func sail(
        at angle: Double,
        bracket: (wind: Double, lastUp: Double, firstDown: Double)
    ) -> TheoreticalSailCombination? {
        if angle <= bracket.lastUp { return .up }
        if angle >= bracket.firstDown { return .down }
        return nil
    }
}
