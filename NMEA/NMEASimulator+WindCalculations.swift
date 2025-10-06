import Foundation

extension NMEASimulator {

    // MARK: - Wind Derived Outputs

    var calculatedTWA: Double? {
        guard let twd = twd.value, let heading = heading.value else { return nil }
        return normalizeAngle(twd - heading)
    }

    var calculatedAWS: Double? {
        guard
            let twd = twd.value,
            let heading = heading.value,
            let tws = tws.value,
            let boatSpeed = speed.value
        else { return nil }

        let awaRad = toRadians(normalizeAngle(twd - heading))
        let windX = tws * cos(awaRad)
        let windY = tws * sin(awaRad)

        let awsX = windX + boatSpeed
        let awsY = windY

        return sqrt(pow(awsX, 2) + pow(awsY, 2))
    }

    var calculatedAWA: Double? {
        guard
            let twd = twd.value,
            let heading = heading.value,
            let tws = tws.value,
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
