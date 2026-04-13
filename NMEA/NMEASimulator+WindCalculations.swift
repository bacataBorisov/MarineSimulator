import Foundation

extension NMEASimulator {

    /// Relative wind vs. the same heading basis as the map (`geographicBearingDegreesForMap`): gyro/true, else magnetic without variation, else COG.
    var calculatedTWA: Double? { computeTWA(from: displaySnapshot, forInstrumentDisplay: true) }
    var calculatedAWS: Double? { computeAWS(from: displaySnapshot, forInstrumentDisplay: true) }
    var calculatedAWA: Double? { computeAWA(from: displaySnapshot, forInstrumentDisplay: true) }
    var calculatedAWD: Double? { computeAWD(from: displaySnapshot, forInstrumentDisplay: true) }
    var calculatedTWS: Double? { computeTWS(from: displaySnapshot) }
    var calculatedTWD: Double? { computeTWD(from: displaySnapshot) }
    var calculatedTWDCompassPoint: String? { compassPoint(for: calculatedTWD) }
    var displayedSeaTemperature: Double? { displaySnapshot?.seaTemperature }
    var displayedAirTemperature: Double? { displaySnapshot?.airTemperature }
    var displayedRelativeHumidity: Double? { displaySnapshot?.relativeHumidity }
    var displayedAirPressure: Double? { displaySnapshot?.airPressure }
    var displayedWindGustSpeed: Double? { weatherSourceMode == .liveWeather ? latestLiveWeather?.windGustSpeedKnots : nil }
    var calculatedVPWKnots: Double? { computeVPWKnots(from: displaySnapshot, forInstrumentDisplay: true) }
    var calculatedVPWMS: Double? { computeVPWMS(from: displaySnapshot, forInstrumentDisplay: true) }

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
            windDirectionTrue: sensorToggles.hasAnemometer ? (twd.value ?? fallbackLiveWeather?.trueWindDirection ?? twd.centerValue) : nil,
            windSpeedTrue: sensorToggles.hasAnemometer ? (tws.value ?? fallbackLiveWeather?.trueWindSpeedKnots ?? tws.centerValue) : nil,
            magneticHeading: sensorToggles.hasCompass ? (heading.value ?? heading.centerValue) : nil,
            gyroHeading: sensorToggles.hasGyro ? (gyroHeading.value ?? gyroHeading.centerValue) : nil,
            magneticVariation: latestSnapshot?.magneticVariation ?? 0,
            compassDeviation: latestSnapshot?.compassDeviation ?? 0,
            boatSpeed: sensorToggles.hasSpeedLog ? (speed.value ?? speed.centerValue) : nil,
            depth: sensorToggles.hasEchoSounder ? (depth.value ?? depth.centerValue) : nil,
            seaTemperature: sensorToggles.hasWaterTempSensor ? (seaTemp.value ?? fallbackLiveWeather?.seaSurfaceTemperatureCelsius ?? seaTemp.centerValue) : nil,
            airTemperature: sensorToggles.hasAirTempSensor ? (airTemp.value ?? fallbackLiveWeather?.airTemperatureCelsius ?? airTemp.centerValue) : nil,
            relativeHumidity: sensorToggles.hasHumidtySensor ? (humidity.value ?? fallbackLiveWeather?.relativeHumidityPercent ?? humidity.centerValue) : nil,
            airPressure: sensorToggles.hasBarometer ? (barometer.value ?? fallbackLiveWeather?.airPressureHectopascals ?? barometer.centerValue) : nil,
            gpsData: gpsData,
            gpsSignal: fallbackSignal,
            turnRate: latestSnapshot?.turnRate ?? 0,
            logDistanceNm: latestSnapshot?.logDistanceNm ?? 0,
            tripDistanceNm: latestSnapshot?.tripDistanceNm ?? 0
        )
    }

    func computeTWA(from snapshot: SimulationSnapshot?, forInstrumentDisplay: Bool = false) -> Double? {
        guard let snapshot, let twd = snapshot.windDirectionTrue else { return nil }

        let heading = forInstrumentDisplay
            ? resolvedHeadingForInstrumentWindAngles(in: snapshot)
            : resolvedTrueHeadingForWind(in: snapshot)

        guard let heading else {
            return twd
        }

        return normalizeAngle(twd - heading)
    }

    func computeAWS(from snapshot: SimulationSnapshot?, forInstrumentDisplay: Bool = false) -> Double? {
        guard let snapshot, let tws = snapshot.windSpeedTrue else { return nil }

        if snapshot.boatSpeed == nil || snapshot.boatSpeed == 0 {
            return tws
        }

        let heading = forInstrumentDisplay
            ? resolvedHeadingForInstrumentWindAngles(in: snapshot)
            : resolvedTrueHeadingForWind(in: snapshot)

        guard
            let twd = snapshot.windDirectionTrue,
            let heading,
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

    func computeAWA(from snapshot: SimulationSnapshot?, forInstrumentDisplay: Bool = false) -> Double? {
        guard let snapshot, let tws = snapshot.windSpeedTrue else { return nil }

        let heading = forInstrumentDisplay
            ? resolvedHeadingForInstrumentWindAngles(in: snapshot)
            : resolvedTrueHeadingForWind(in: snapshot)

        if snapshot.boatSpeed == nil || snapshot.boatSpeed == 0 {
            if let twd = snapshot.windDirectionTrue, let heading {
                return normalizeAngle(twd - heading)
            }
            return snapshot.windDirectionTrue
        }

        guard
            let twd = snapshot.windDirectionTrue,
            let heading,
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

    func computeAWD(from snapshot: SimulationSnapshot?, forInstrumentDisplay: Bool = false) -> Double? {
        guard let snapshot else { return nil }
        let heading = forInstrumentDisplay
            ? resolvedHeadingForInstrumentWindAngles(in: snapshot)
            : resolvedTrueHeadingForWind(in: snapshot)
        guard let heading, let awa = computeAWA(from: snapshot, forInstrumentDisplay: forInstrumentDisplay) else {
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

    func computeVPWKnots(from snapshot: SimulationSnapshot?, forInstrumentDisplay: Bool = false) -> Double? {
        guard let snapshot, let tws = snapshot.windSpeedTrue, let twa = computeTWA(from: snapshot, forInstrumentDisplay: forInstrumentDisplay) else {
            return nil
        }
        return tws * cos(toRadians(twa))
    }

    func computeVPWMS(from snapshot: SimulationSnapshot?, forInstrumentDisplay: Bool = false) -> Double? {
        guard let vpwKnots = computeVPWKnots(from: snapshot, forInstrumentDisplay: forInstrumentDisplay) else {
            return nil
        }
        return vpwKnots * 0.514444
    }

    func compassPoint(for direction: Double?) -> String? {
        guard let direction else {
            return nil
        }

        let normalized = normalizeAngle(direction)
        let points = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]
        let index = Int((normalized + 11.25) / 22.5) % points.count
        return points[index]
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

    /// Matches `geographicBearingDegreesForMap`: bow direction shown on the chart vs. numeric heading sliders (gyro as true; magnetic uncorrected for variation; else COG).
    private func resolvedHeadingForInstrumentWindAngles(in snapshot: SimulationSnapshot) -> Double? {
        if let gyroHeading = snapshot.gyroHeading {
            return normalizeAngle(gyroHeading)
        }

        if let magneticHeading = snapshot.magneticHeading {
            return normalizeAngle(magneticHeading)
        }

        return normalizeAngle(snapshot.gpsData.courseOverGround)
    }
}
