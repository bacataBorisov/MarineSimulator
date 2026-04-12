import Foundation

extension NMEASimulator {

    var calculatedTWA: Double? { computeTWA(from: displaySnapshot) }
    var calculatedAWS: Double? { computeAWS(from: displaySnapshot) }
    var calculatedAWA: Double? { computeAWA(from: displaySnapshot) }
    var calculatedAWD: Double? { computeAWD(from: displaySnapshot) }
    var calculatedTWS: Double? { computeTWS(from: displaySnapshot) }
    var calculatedTWD: Double? { computeTWD(from: displaySnapshot) }
    var displayedSeaTemperature: Double? { displaySnapshot?.seaTemperature }
    var calculatedVPWKnots: Double? { computeVPWKnots(from: displaySnapshot) }
    var calculatedVPWMS: Double? { computeVPWMS(from: displaySnapshot) }

    private var displaySnapshot: SimulationSnapshot? {
        if isTransmitting, let latestSnapshot {
            return latestSnapshot
        }

        let fallbackLiveWeather = weatherSourceMode == .liveWeather ? latestLiveWeather : nil

        let fallbackSignal = latestSnapshot?.gpsSignal ?? GPSSignalSnapshot(
            fixQuality: sensorToggles.hasGPS ? 1 : 0,
            fixMode: sensorToggles.hasGPS ? 3 : 1,
            selectionMode: sensorToggles.hasGPS ? "A" : "M",
            satellitesUsed: sensorToggles.hasGPS ? 8 : 0,
            hdop: sensorToggles.hasGPS ? 0.9 : 99.9,
            vdop: sensorToggles.hasGPS ? 1.1 : 99.9,
            pdop: sensorToggles.hasGPS ? 1.4 : 99.9,
            altitudeMeters: 0,
            geoidalSeparationMeters: 0,
            satellites: []
        )

        return SimulationSnapshot(
            timestamp: Date(),
            windDirectionTrue: sensorToggles.hasAnemometer ? (fallbackLiveWeather?.trueWindDirection ?? twd.value ?? twd.centerValue) : nil,
            windSpeedTrue: sensorToggles.hasAnemometer ? (fallbackLiveWeather?.trueWindSpeedKnots ?? tws.value ?? tws.centerValue) : nil,
            magneticHeading: sensorToggles.hasCompass ? (heading.value ?? heading.centerValue) : nil,
            gyroHeading: sensorToggles.hasGyro ? (gyroHeading.value ?? gyroHeading.centerValue) : nil,
            magneticVariation: latestSnapshot?.magneticVariation ?? 0,
            compassDeviation: latestSnapshot?.compassDeviation ?? 0,
            boatSpeed: sensorToggles.hasSpeedLog ? (speed.value ?? speed.centerValue) : nil,
            depth: sensorToggles.hasEchoSounder ? (depth.value ?? depth.centerValue) : nil,
            seaTemperature: sensorToggles.hasWaterTempSensor ? (fallbackLiveWeather?.seaSurfaceTemperatureCelsius ?? seaTemp.value ?? seaTemp.centerValue) : nil,
            gpsData: gpsData,
            gpsSignal: fallbackSignal,
            turnRate: latestSnapshot?.turnRate ?? 0,
            logDistanceNm: latestSnapshot?.logDistanceNm ?? 0,
            tripDistanceNm: latestSnapshot?.tripDistanceNm ?? 0
        )
    }

    func computeTWA(from snapshot: SimulationSnapshot?) -> Double? {
        guard let snapshot, let twd = snapshot.windDirectionTrue else { return nil }

        guard let heading = resolvedTrueHeadingForWind(in: snapshot) else {
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
            let heading = resolvedTrueHeadingForWind(in: snapshot),
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
            if let twd = snapshot.windDirectionTrue, let heading = resolvedTrueHeadingForWind(in: snapshot) {
                return normalizeAngle(twd - heading)
            }
            return snapshot.windDirectionTrue
        }

        guard
            let twd = snapshot.windDirectionTrue,
            let heading = resolvedTrueHeadingForWind(in: snapshot),
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
        guard let snapshot, let heading = resolvedTrueHeadingForWind(in: snapshot), let awa = computeAWA(from: snapshot) else {
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

    private func resolvedTrueHeadingForWind(in snapshot: SimulationSnapshot) -> Double? {
        if let gyroHeading = snapshot.gyroHeading {
            return normalizeAngle(gyroHeading)
        }

        guard let magneticHeading = snapshot.magneticHeading else {
            return nil
        }

        return normalizeAngle(magneticHeading + snapshot.magneticVariation)
    }
}
