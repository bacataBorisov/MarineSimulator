import Foundation

extension NMEASimulator {

    var calculatedTWA: Double? { computeTWA(from: latestSnapshot) }
    var calculatedAWS: Double? { computeAWS(from: latestSnapshot) }
    var calculatedAWA: Double? { computeAWA(from: latestSnapshot) }
    var calculatedAWD: Double? { computeAWD(from: latestSnapshot) }
    var calculatedTWS: Double? { computeTWS(from: latestSnapshot) }
    var calculatedTWD: Double? { computeTWD(from: latestSnapshot) }
    var calculatedVPWKnots: Double? { computeVPWKnots(from: latestSnapshot) }
    var calculatedVPWMS: Double? { computeVPWMS(from: latestSnapshot) }

    func computeTWA(from snapshot: SimulationSnapshot?) -> Double? {
        guard let snapshot, let twd = snapshot.windDirectionTrue else { return nil }

        if snapshot.boatSpeed == nil || snapshot.boatSpeed == 0 {
            return twd
        }

        guard let heading = snapshot.gyroHeading ?? snapshot.magneticHeading else {
            return twd
        }

        return normalizeAngle(twd - heading)
    }

    func computeAWS(from snapshot: SimulationSnapshot?) -> Double? {
        guard let snapshot, let tws = snapshot.windSpeedTrue else { return nil }

        if snapshot.boatSpeed == nil || snapshot.boatSpeed == 0 {
            return tws
        }

        guard
            let twd = snapshot.windDirectionTrue,
            let heading = snapshot.gyroHeading ?? snapshot.magneticHeading,
            let boatSpeed = snapshot.boatSpeed
        else {
            return tws
        }

        let twaRad = toRadians(normalizeAngle(twd - heading))
        let windX = tws * cos(twaRad)
        let windY = tws * sin(twaRad)
        let apparentX = windX + boatSpeed
        let apparentY = windY

        return sqrt(apparentX * apparentX + apparentY * apparentY)
    }

    func computeAWA(from snapshot: SimulationSnapshot?) -> Double? {
        guard let snapshot, let tws = snapshot.windSpeedTrue else { return nil }

        if snapshot.boatSpeed == nil || snapshot.boatSpeed == 0 {
            if let twd = snapshot.windDirectionTrue, let heading = snapshot.gyroHeading ?? snapshot.magneticHeading {
                return normalizeAngle(twd - heading)
            }
            return snapshot.windDirectionTrue
        }

        guard
            let twd = snapshot.windDirectionTrue,
            let heading = snapshot.gyroHeading ?? snapshot.magneticHeading,
            let boatSpeed = snapshot.boatSpeed
        else {
            return nil
        }

        let twa = normalizeAngle(twd - heading)
        let twaRad = toRadians(twa)
        let windX = tws * cos(twaRad)
        let windY = tws * sin(twaRad)
        let apparentX = windX + boatSpeed
        let apparentY = windY
        return normalizeAngle(toDegrees(atan2(apparentY, apparentX)))
    }

    func computeAWD(from snapshot: SimulationSnapshot?) -> Double? {
        guard let snapshot, let heading = snapshot.gyroHeading ?? snapshot.magneticHeading, let awa = computeAWA(from: snapshot) else {
            return nil
        }
        return normalizeAngle(heading + awa)
    }

    func computeTWS(from snapshot: SimulationSnapshot?) -> Double? {
        snapshot?.windSpeedTrue
    }

    func computeTWD(from snapshot: SimulationSnapshot?) -> Double? {
        snapshot?.windDirectionTrue
    }

    func computeVPWKnots(from snapshot: SimulationSnapshot?) -> Double? {
        guard let snapshot, let tws = snapshot.windSpeedTrue, let twa = computeTWA(from: snapshot) else {
            return nil
        }
        return tws * cos(toRadians(twa))
    }

    func computeVPWMS(from snapshot: SimulationSnapshot?) -> Double? {
        guard let vpwKnots = computeVPWKnots(from: snapshot) else {
            return nil
        }
        return vpwKnots * 0.514444
    }
}
