import Foundation

/// Physics-based parametric VPP prior generated solely from a vessel's hull,
/// rig, and sail-area dimensions — without reading any manufacturer polar table.
///
/// Intended as a cold-start baseline for vessels without a VPP table (or to test
/// how closely first-principles dimensions + adaptive NMEA recovery match Farr #354).
struct ParametricPolarGenerator: Equatable, Sendable {
    struct Summary: Equatable, Sendable {
        var waterlineLengthMeters: Double
        var displacementKilograms: Double
        var upwindSailAreaSquareMeters: Double
        var downwindSailAreaSquareMeters: Double
        var hullSpeedKnots: Double
        var sailAreaToDisplacementRatio: Double
        var displacementToLengthRatio: Double
    }

    var summary: Summary

    init?(vessel: VesselProfile) {
        guard let loa = vessel.hull.lengthOverallMeters ?? vessel.hull.waterlineLengthMeters,
              loa.isFinite, loa > 2,
              let displacementKg = vessel.hull.displacementKilograms,
              displacementKg.isFinite, displacementKg > 200 else {
            return nil
        }

        let lwl = vessel.hull.waterlineLengthMeters ?? (loa * 0.89)
        let upwindArea = Self.estimateUpwindSailArea(vessel: vessel, loa: loa)
        let downwindArea = Self.estimateDownwindSailArea(vessel: vessel, upwindArea: upwindArea)

        // Classical displacement hull speed: 1.34 * sqrt(LWL_ft)
        let lwlFeet = lwl * 3.28084
        let hullSpeedKnots = 1.34 * sqrt(lwlFeet)

        // Standard naval architecture ratios (Imperial units)
        let displacementLongTons = displacementKg / 1_016.0469
        let dispLbs = displacementKg * 2.2046226
        let saSqFt = upwindArea * 10.76391
        let volumeCuFt = dispLbs / 64.0
        let sad = saSqFt / pow(volumeCuFt, 2.0 / 3.0)
        let dlr = displacementLongTons / pow(0.01 * lwlFeet, 3.0)

        self.summary = Summary(
            waterlineLengthMeters: lwl,
            displacementKilograms: displacementKg,
            upwindSailAreaSquareMeters: upwindArea,
            downwindSailAreaSquareMeters: downwindArea,
            hullSpeedKnots: hullSpeedKnots,
            sailAreaToDisplacementRatio: sad,
            displacementToLengthRatio: dlr
        )
    }

    /// Solves longitudinal aero-hydrodynamic force equilibrium in knots for (TWS, TWA).
    func predictedSpeedKnots(trueWindSpeedKnots: Double, trueWindAngleDegrees: Double) -> Double {
        guard trueWindSpeedKnots.isFinite, trueWindSpeedKnots > 0,
              trueWindAngleDegrees.isFinite else { return 0 }

        let absTWA = abs(trueWindAngleDegrees.truncatingRemainder(dividingBy: 360))
        let twa = absTWA > 180 ? 360 - absTWA : absTWA
        guard twa > 1 else { return 0 }

        let twsMS = trueWindSpeedKnots * 0.514444
        let twaRad = twa * Double.pi / 180.0

        // Smoothly transition from working sails (main + jib) to downwind spinnaker between 100° and 135° TWA.
        let spinnakerBlend = ((twa - 100.0) / 35.0).clamped(to: 0...1)
        let smoothBlend = spinnakerBlend * spinnakerBlend * (3 - 2 * spinnakerBlend)
        let activeSailArea = summary.upwindSailAreaSquareMeters
            + (summary.downwindSailAreaSquareMeters - summary.upwindSailAreaSquareMeters) * smoothBlend

        // Wetted surface area (Delft canoe body + keel/rudder appendages ~ +25%)
        let volumeM3 = summary.displacementKilograms / 1_025.0
        let wettedSurface = 3.25 * sqrt(volumeM3 * summary.waterlineLengthMeters)

        let maxSpeedMS = summary.hullSpeedKnots * 1.45 * 0.514444
        var low = 0.0
        var high = max(maxSpeedMS, twsMS * 1.1)

        for _ in 0..<28 {
            let mid = 0.5 * (low + high)
            let netForce = aerodynamicDriveForce(
                boatSpeedMS: mid,
                trueWindSpeedMS: twsMS,
                twaRad: twaRad,
                twaDeg: twa,
                sailArea: activeSailArea,
                spinnakerBlend: smoothBlend
            ) - hydrodynamicDragForce(
                boatSpeedMS: mid,
                wettedSurface: wettedSurface,
                twaDeg: twa
            )

            if netForce > 0 {
                low = mid
            } else {
                high = mid
            }
        }

        let solvedKnots = 0.5 * (low + high) / 0.514444
        if twa < 33 {
            let ratio = twa / 33.0
            return solvedKnots * ratio * ratio
        }
        return max(0, solvedKnots)
    }

    private func aerodynamicDriveForce(
        boatSpeedMS: Double,
        trueWindSpeedMS: Double,
        twaRad: Double,
        twaDeg: Double,
        sailArea: Double,
        spinnakerBlend: Double
    ) -> Double {
        let airDensity = 1.225 // kg/m^3
        // Apparent wind in boat frame (assuming modest windage/gradient)
        let awsX = trueWindSpeedMS * cos(twaRad) + boatSpeedMS
        let awsY = trueWindSpeedMS * sin(twaRad)
        let aws = hypot(awsX, awsY)
        let awaRad = atan2(awsY, awsX)
        let awaDeg = awaRad * 180.0 / Double.pi

        // Classical ORC/Hazen lift & drag curves vs AWA:
        // Lift peaks ~1.25 around 35–60° AWA and falls to 0 at 180° AWA.
        // Drag starts ~0.16 close-hauled (induced + parasitic) and rises to ~1.10 dead downwind.
        let stallFactor = ((awaDeg - 15.0) / 14.0).clamped(to: 0...1)
        let cl = (1.30 * sin(min(awaRad * 1.35, Double.pi)) * stallFactor).clamped(to: 0...1.35)
        let cdBase = 0.14 + 0.96 * pow(sin(0.5 * awaRad), 1.6)
        let cd = cdBase + 0.12 * spinnakerBlend

        // Longitudinal driving force coefficient: C_X = C_L * sin(AWA) - C_D * cos(AWA)
        let cx = max(0, cl * sin(awaRad) - cd * cos(awaRad))

        // Righting-moment / reefing depowering in stronger wind (more pronounced upwind & close reach)
        let twsKnots = trueWindSpeedMS / 0.514444
        let upwindHeelWeight = max(0.15, 1.0 - max(0, twaDeg - 45) / 135.0)
        let depower = 1.0 / (1.0 + pow(max(0, twsKnots - 12.0) / 15.0, 1.8) * upwindHeelWeight)

        return 0.5 * airDensity * aws * aws * sailArea * cx * depower
    }

    private func hydrodynamicDragForce(
        boatSpeedMS: Double,
        wettedSurface: Double,
        twaDeg: Double
    ) -> Double {
        let waterDensity = 1_025.0 // kg/m^3
        let hullSpeedMS = summary.hullSpeedKnots * 0.514444
        let froudeNormalized = boatSpeedMS / max(hullSpeedMS, 0.5)

        // Turbulent skin friction + appendage form drag
        let frictionCoeff = 0.0034
        let frictionDrag = 0.5 * waterDensity * boatSpeedMS * boatSpeedMS * wettedSurface * frictionCoeff

        // Induced keel drag + heel resistance (highest close-hauled, zero dead downwind)
        let sideLoadFactor = pow(max(0, 1.0 - max(0, twaDeg - 35.0) / 120.0), 1.4)
        let inducedDrag = frictionDrag * (0.55 * sideLoadFactor)

        // Delft-style residuary (wave-making) drag wall rising steeply as boat approaches hull speed (Fn ~ 0.40)
        let dlrScale = (summary.displacementToLengthRatio / 155.0).clamped(to: 0.65...1.6)
        let downwindSurfRelief = 1.0 - 0.25 * ((twaDeg - 120.0) / 60.0).clamped(to: 0...1)
        let waveWall = 0.5 * waterDensity * boatSpeedMS * boatSpeedMS * wettedSurface * 0.0115
            * pow(max(0, froudeNormalized), 4.8) * dlrScale * downwindSurfRelief

        return frictionDrag + inducedDrag + waveWall
    }

    private static func estimateUpwindSailArea(vessel: VesselProfile, loa: Double) -> Double {
        let mainArea = vessel.inventory.first(where: { $0.category == .mainsail })?.mainsail?.areaSquareMeters
            ?? {
                guard let p = vessel.rig.mainsailLuffMeters, let e = vessel.rig.mainsailFootMeters else {
                    return 0.58 * loa * loa * 0.55
                }
                return 0.56 * p * e
            }()

        let headsailArea = vessel.inventory
            .filter { $0.category == .headsail }
            .compactMap { $0.headsail?.areaSquareMeters }
            .max()
            ?? {
                guard let j = vessel.rig.foretriangleBaseMeters else {
                    return 0.55 * mainArea
                }
                let i = vessel.rig.foretriangleHeightMeters ?? (loa * 1.28)
                return 0.5 * i * j * 1.08
            }()

        return mainArea + headsailArea
    }

    private static func estimateDownwindSailArea(vessel: VesselProfile, upwindArea: Double) -> Double {
        let mainArea = vessel.inventory.first(where: { $0.category == .mainsail })?.mainsail?.areaSquareMeters
            ?? (upwindArea * 0.55)
        if let biggestSpinnaker = vessel.inventory
            .filter({ $0.category.fitsDownwindSlot })
            .compactMap({ $0.downwind?.areaSquareMeters })
            .max() {
            return mainArea + biggestSpinnaker
        }
        return upwindArea * 2.1
    }
}
