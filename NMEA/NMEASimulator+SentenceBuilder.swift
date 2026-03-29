import Foundation

extension NMEASimulator {

    enum NMEASentenceType: String, CaseIterable {
        case mwv
        case mwd
        case vpw
        case hdg
        case hdt
        case rot
        case rmc
        case gga
        case vtg
        case gll
        case gsa
        case gsv
        case zda
        case dbt
        case dpt
        case vhw
        case vbw
        case vlw
        case mtw
    }

    func buildNMEASentence(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> String? {
        let payload: String?

        switch type {
        case .mwv, .mwd, .vpw:
            payload = buildWindSentence(talkerID: talkerID, type: type, snapshot: snapshot)
        case .hdg:
            payload = buildHDGSentence(talkerID: talkerID, snapshot: snapshot)
        case .hdt, .rot:
            payload = buildGyroSentence(talkerID: talkerID, type: type, snapshot: snapshot)
        case .rmc, .gga, .vtg, .gll, .gsa, .gsv, .zda:
            payload = buildGPSSentence(talkerID: talkerID, type: type, snapshot: snapshot)
        case .dbt, .dpt, .vhw, .vbw, .vlw, .mtw:
            payload = buildHydroSentence(talkerID: talkerID, type: type, snapshot: snapshot)
        }

        guard let payload, !payload.isEmpty else {
            return nil
        }

        return addChecksum(to: payload)
    }

    private func buildWindSentence(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> String? {
        switch type {
        case .mwv:
            let reference = nextMWVReference(in: snapshot)
            if reference == "R" {
                guard let awa = computeAWA(from: snapshot), let aws = computeAWS(from: snapshot) else { return nil }
                return "$\(talkerID)MWV,\(String(format: "%.0f", awa)),R,\(String(format: "%.1f", aws)),N,A"
            }

            guard let twa = computeTWA(from: snapshot), let tws = computeTWS(from: snapshot) else { return nil }
            return "$\(talkerID)MWV,\(String(format: "%.0f", twa)),T,\(String(format: "%.1f", tws)),N,A"

        case .mwd:
            guard let twd = computeTWD(from: snapshot), let tws = computeTWS(from: snapshot) else { return nil }
            return "$\(talkerID)MWD,\(String(format: "%.0f", twd)),T,,M,\(String(format: "%.1f", tws)),N,,M"

        case .vpw:
            guard let vpwKnots = computeVPWKnots(from: snapshot), let vpwMS = computeVPWMS(from: snapshot) else { return nil }
            return "$\(talkerID)VPW,\(String(format: "%.1f", vpwKnots)),N,\(String(format: "%.1f", vpwMS)),M"

        default:
            return nil
        }
    }

    private func buildHDGSentence(talkerID: String, snapshot: SimulationSnapshot) -> String? {
        guard let headingMag = snapshot.magneticHeading else {
            return nil
        }

        let deviationDeg = 2.0
        let variationDeg = 3.0

        return "$\(talkerID)HDG,\(String(format: "%.1f", headingMag)),\(String(format: "%.1f", deviationDeg)),E,\(String(format: "%.1f", variationDeg)),W"
    }

    private func buildGyroSentence(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> String? {
        switch type {
        case .hdt:
            guard let headingTrue = resolvedTrueHeading(in: snapshot) else {
                return nil
            }
            return "$\(talkerID)HDT,\(String(format: "%.1f", headingTrue)),T"

        case .rot:
            let status = abs(snapshot.turnRate) < 0.01 ? "V" : "A"
            return "$\(talkerID)ROT,\(String(format: "%.1f", snapshot.turnRate)),\(status)"

        default:
            return nil
        }
    }

    private func buildHydroSentence(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> String? {
        switch type {
        case .dbt:
            guard let depthMeters = snapshot.depth else { return nil }
            let depthFeet = depthMeters * 3.28084
            let depthFathoms = depthMeters / 1.8288
            return "$\(talkerID)DBT,\(String(format: "%.1f", depthFeet)),f,\(String(format: "%.1f", depthMeters)),M,\(String(format: "%.1f", depthFathoms)),F"

        case .dpt:
            guard let depthMeters = snapshot.depth else { return nil }
            return "$\(talkerID)DPT,\(String(format: "%.1f", depthMeters)),\(String(format: "%.1f", depthOffsetMeters))"

        case .mtw:
            guard let seaTemperature = snapshot.seaTemperature else { return nil }
            return "$\(talkerID)MTW,\(String(format: "%.1f", seaTemperature)),C"

        case .vhw:
            let headingTrue = resolvedTrueHeading(in: snapshot)
            let headingMag = snapshot.magneticHeading
            let speedKnots = snapshot.boatSpeed
            let speedKMH = speedKnots.map { $0 * 1.852 }

            return "$\(talkerID)VHW,\(formatted(headingTrue, decimals: 1)),T,\(formatted(headingMag, decimals: 1)),M,\(formatted(speedKnots, decimals: 1)),N,\(formatted(speedKMH, decimals: 1)),K"

        case .vbw:
            let longWater = snapshot.boatSpeed
            let longGround = snapshot.gpsData.speedOverGround
            let waterStatus = longWater == nil ? "V" : "A"
            let groundStatus = sensorToggles.hasGPS ? "A" : "V"

            return "$\(talkerID)VBW,\(formatted(longWater, decimals: 1)),0.0,\(waterStatus),\(formatted(longGround, decimals: 1)),0.0,\(groundStatus)"

        case .vlw:
            return "$\(talkerID)VLW,\(String(format: "%.2f", snapshot.logDistanceNm)),N,\(String(format: "%.2f", snapshot.tripDistanceNm)),N"

        default:
            return nil
        }
    }

    private func buildGPSSentence(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> String? {
        let timeString = utcTimeString(from: snapshot.timestamp)
        let dateString = utcDateString(from: snapshot.timestamp)
        let latitude = snapshot.gpsData.latitude
        let longitude = snapshot.gpsData.longitude
        let latString = FormatKit.formatLatitude(latitude)
        let lonString = FormatKit.formatLongitude(longitude)
        let cogString = String(format: "%.1f", snapshot.gpsData.courseOverGround)
        let sogString = String(format: "%.1f", snapshot.gpsData.speedOverGround)

        switch type {
        case .rmc:
            return "$\(talkerID)RMC,\(timeString),A,\(latString),\(lonString),\(sogString),\(cogString),\(dateString),,,A"

        case .gga:
            return "$\(talkerID)GGA,\(timeString),\(latString),\(lonString),1,10,0.9,5.0,M,0.0,M,,"

        case .vtg:
            let magneticCourse = normalizedMagneticCourse(fromTrue: snapshot.gpsData.courseOverGround)
            return "$\(talkerID)VTG,\(cogString),T,\(String(format: "%.1f", magneticCourse)),M,\(sogString),N,\(String(format: "%.1f", snapshot.gpsData.speedOverGround * 1.852)),K,A"

        case .gll:
            return "$\(talkerID)GLL,\(latString),\(lonString),\(timeString),A,A"

        case .gsa:
            return "$\(talkerID)GSA,A,3,01,03,05,07,09,11,13,15,17,19,,,,1.2,0.9,0.8"

        case .gsv:
            return "$\(talkerID)GSV,2,1,10,01,45,180,42,03,60,045,40,05,30,270,38,07,15,100,35"

        case .zda:
            let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: snapshot.timestamp)
            return "$\(talkerID)ZDA,\(timeString),\(String(format: "%02d", components.day ?? 0)),\(String(format: "%02d", components.month ?? 0)),\(components.year ?? 0),00,00"

        default:
            return nil
        }
    }

    private func resolvedTrueHeading(in snapshot: SimulationSnapshot) -> Double? {
        if let gyroHeading = snapshot.gyroHeading {
            return normalizeAngle(gyroHeading)
        }

        guard let magneticHeading = snapshot.magneticHeading else {
            return nil
        }

        return normalizeAngle(magneticHeading - 3.0)
    }

    private func normalizedMagneticCourse(fromTrue trueCourse: Double) -> Double {
        normalizeAngle(trueCourse + 3.0)
    }

    private func utcTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HHmmss.SS"
        return formatter.string(from: date)
    }

    private func utcDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "ddMMyy"
        return formatter.string(from: date)
    }

    private func formatted(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    private func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }
}
