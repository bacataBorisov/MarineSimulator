import Foundation

extension NMEASimulator {

    // MARK: - Wind Derived Outputs

    var calculatedTWA: Double? {
        guard let twd = twd.value else { return nil }

        // If boat is not moving or speed unavailable → heading irrelevant
        if speed.value == nil || speed.value == 0 {
            return twd
        }

        guard let heading = heading.value else { return twd }
        return normalizeAngle(twd - heading)
    }

    var calculatedAWS: Double? {
        guard let tws = tws.value else { return nil }

        // If boat is stationary or missing data → AWS = TWS
        if speed.value == nil || speed.value == 0 {
            return tws
        }

        guard
            let twd = twd.value,
            let heading = heading.value,
            let boatSpeed = speed.value
        else { return tws }

        let awaRad = toRadians(normalizeAngle(twd - heading))
        let windX = tws * cos(awaRad)
        let windY = tws * sin(awaRad)

        let awsX = windX + boatSpeed
        let awsY = windY

        return sqrt(awsX * awsX + awsY * awsY)
    }

    var calculatedAWA: Double? {
        // If we have no wind data at all
        guard let tws = tws.value else { return nil }

        // Case 1: boat speed missing or zero → AWA = TWA (or TWD if heading missing)
        if speed.value == nil || speed.value == 0 {
            if let twd = twd.value, let heading = heading.value {
                return normalizeAngle(twd - heading)
            } else if let twd = twd.value {
                // no heading → use absolute wind direction
                return twd
            } else {
                return nil
            }
        }

        // Case 2: moving → do full calculation
        guard
            let twd = twd.value,
            let heading = heading.value,
            let boatSpeed = speed.value
        else { return nil }

        let twa = normalizeAngle(twd - heading)
        let twaRad = toRadians(twa)

        let windX = tws * cos(twaRad)
        let windY = tws * sin(twaRad)

        let apparentX = windX + boatSpeed
        let apparentY = windY

        let awaRad = atan2(apparentY, apparentX)
        let degrees = toDegrees(awaRad)
        return normalizeAngle(degrees)
    }
    var calculatedAWD: Double? {
        guard let heading = heading.value, let awa = calculatedAWA else { return nil }
        return normalizeAngle(heading + awa)
    }

    var calculatedTWS: Double? {
        tws.value
    }

    var calculatedTWD: Double? {
        twd.value
    }

    var calculatedVPWKnots: Double? {
        guard let tws = tws.value, let twa = calculatedTWA else { return nil }
        return tws * cos(toRadians(twa))
    }

    var calculatedVPWMS: Double? {
        guard let vpwKnots = calculatedVPWKnots else { return nil }
        return vpwKnots * 0.514444 // knots to m/s
    }
}
