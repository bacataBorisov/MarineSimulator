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

    func buildNMEASentences(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> [String] {
        let payloads: [String]

        switch type {
        case .mwv, .mwd, .vpw:
            payloads = buildWindSentences(talkerID: talkerID, type: type, snapshot: snapshot)
        case .hdg:
            payloads = buildHDGSentences(talkerID: talkerID, snapshot: snapshot)
        case .hdt, .rot:
            payloads = buildGyroSentences(talkerID: talkerID, type: type, snapshot: snapshot)
        case .rmc, .gga, .vtg, .gll, .gsa, .gsv, .zda:
            payloads = buildGPSSentences(talkerID: talkerID, type: type, snapshot: snapshot)
        case .dbt, .dpt, .vhw, .vbw, .vlw, .mtw:
            payloads = buildHydroSentences(talkerID: talkerID, type: type, snapshot: snapshot)
        }

        return payloads
            .filter { !$0.isEmpty }
            .map(addChecksum(to:))
    }

    private func buildWindSentences(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> [String] {
        switch type {
        case .mwv:
            let reference = nextMWVReference(in: snapshot)
            if reference == "R" {
                guard let awa = computeAWA(from: snapshot), let aws = computeAWS(from: snapshot) else { return [] }
                return ["$\(talkerID)MWV,\(String(format: "%.0f", awa)),R,\(String(format: "%.1f", aws)),N,A"]
            }

            guard let twa = computeTWA(from: snapshot), let tws = computeTWS(from: snapshot) else { return [] }
            return ["$\(talkerID)MWV,\(String(format: "%.0f", twa)),T,\(String(format: "%.1f", tws)),N,A"]

        case .mwd:
            guard let twd = computeTWD(from: snapshot), let tws = computeTWS(from: snapshot) else { return [] }
            let magneticDirection = normalizeAngle(twd - snapshot.magneticVariation)
            return ["$\(talkerID)MWD,\(String(format: "%.1f", twd)),T,\(String(format: "%.1f", magneticDirection)),M,\(String(format: "%.1f", tws)),N,\(String(format: "%.1f", tws * 0.514444)),M"]

        case .vpw:
            guard let vpwKnots = computeVPWKnots(from: snapshot), let vpwMS = computeVPWMS(from: snapshot) else { return [] }
            return ["$\(talkerID)VPW,\(String(format: "%.1f", vpwKnots)),N,\(String(format: "%.1f", vpwMS)),M"]

        default:
            return []
        }
    }

    private func buildHDGSentences(talkerID: String, snapshot: SimulationSnapshot) -> [String] {
        guard let headingMag = snapshot.magneticHeading else {
            return []
        }

        let deviationDeg = abs(snapshot.compassDeviation)
        let deviationHemisphere = snapshot.compassDeviation >= 0 ? "E" : "W"
        let variationDeg = abs(snapshot.magneticVariation)
        let variationHemisphere = snapshot.magneticVariation >= 0 ? "E" : "W"

        return ["$\(talkerID)HDG,\(String(format: "%.1f", headingMag)),\(String(format: "%.1f", deviationDeg)),\(deviationHemisphere),\(String(format: "%.1f", variationDeg)),\(variationHemisphere)"]
    }

    private func buildGyroSentences(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> [String] {
        switch type {
        case .hdt:
            guard let headingTrue = resolvedTrueHeading(in: snapshot) else {
                return []
            }
            return ["$\(talkerID)HDT,\(String(format: "%.1f", headingTrue)),T"]

        case .rot:
            let status = abs(snapshot.turnRate) < 0.01 ? "V" : "A"
            return ["$\(talkerID)ROT,\(String(format: "%.1f", snapshot.turnRate)),\(status)"]

        default:
            return []
        }
    }

    private func buildHydroSentences(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> [String] {
        switch type {
        case .dbt:
            guard let depthMeters = snapshot.depth else { return [] }
            let depthFeet = depthMeters * 3.28084
            let depthFathoms = depthMeters / 1.8288
            return ["$\(talkerID)DBT,\(String(format: "%.1f", depthFeet)),f,\(String(format: "%.1f", depthMeters)),M,\(String(format: "%.1f", depthFathoms)),F"]

        case .dpt:
            guard let depthMeters = snapshot.depth else { return [] }
            return ["$\(talkerID)DPT,\(String(format: "%.1f", depthMeters)),\(String(format: "%.1f", depthOffsetMeters))"]

        case .mtw:
            guard let seaTemperature = snapshot.seaTemperature else { return [] }
            return ["$\(talkerID)MTW,\(String(format: "%.1f", seaTemperature)),C"]

        case .vhw:
            let headingTrue = resolvedTrueHeading(in: snapshot)
            let headingMag = snapshot.magneticHeading ?? headingTrue.map { normalizeAngle($0 - snapshot.magneticVariation) }
            let speedKnots = snapshot.boatSpeed
            let speedKMH = speedKnots.map { $0 * 1.852 }

            return ["$\(talkerID)VHW,\(formatted(headingTrue, decimals: 1)),T,\(formatted(headingMag, decimals: 1)),M,\(formatted(speedKnots, decimals: 1)),N,\(formatted(speedKMH, decimals: 1)),K"]

        case .vbw:
            let referenceHeading = resolvedTrueHeading(in: snapshot) ?? snapshot.gpsData.courseOverGround
            let waterVector = speedComponents(speedKnots: snapshot.boatSpeed, course: referenceHeading, referenceHeading: referenceHeading)
            let groundVector = sensorToggles.hasGPS
                ? speedComponents(speedKnots: snapshot.gpsData.speedOverGround, course: snapshot.gpsData.courseOverGround, referenceHeading: referenceHeading)
                : (longitudinal: Double?.none, transverse: Double?.none)
            let longWater = waterVector.longitudinal
            let transWater = waterVector.transverse
            let longGround = groundVector.longitudinal
            let transGround = groundVector.transverse
            let waterStatus = longWater == nil ? "V" : "A"
            let groundStatus = sensorToggles.hasGPS ? "A" : "V"

            return ["$\(talkerID)VBW,\(formatted(longWater, decimals: 1)),\(formatted(transWater, decimals: 1)),\(waterStatus),\(formatted(longGround, decimals: 1)),\(formatted(transGround, decimals: 1)),\(groundStatus)"]

        case .vlw:
            return ["$\(talkerID)VLW,\(String(format: "%.2f", snapshot.logDistanceNm)),N,\(String(format: "%.2f", snapshot.tripDistanceNm)),N"]

        default:
            return []
        }
    }

    private func buildGPSSentences(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> [String] {
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
            let variation = abs(snapshot.magneticVariation)
            let variationHemisphere = snapshot.magneticVariation >= 0 ? "E" : "W"
            return ["$\(talkerID)RMC,\(timeString),A,\(latString),\(lonString),\(sogString),\(cogString),\(dateString),\(String(format: "%.1f", variation)),\(variationHemisphere),A"]

        case .gga:
            let gpsSignal = snapshot.gpsSignal
            return ["$\(talkerID)GGA,\(timeString),\(latString),\(lonString),\(gpsSignal.fixQuality),\(String(format: "%02d", gpsSignal.satellitesUsed)),\(String(format: "%.1f", gpsSignal.hdop)),\(String(format: "%.1f", gpsSignal.altitudeMeters)),M,\(String(format: "%.1f", gpsSignal.geoidalSeparationMeters)),M,,"]

        case .vtg:
            let magneticCourse = normalizedMagneticCourse(fromTrue: snapshot.gpsData.courseOverGround, variation: snapshot.magneticVariation)
            return ["$\(talkerID)VTG,\(cogString),T,\(String(format: "%.1f", magneticCourse)),M,\(sogString),N,\(String(format: "%.1f", snapshot.gpsData.speedOverGround * 1.852)),K,A"]

        case .gll:
            return ["$\(talkerID)GLL,\(latString),\(lonString),\(timeString),A,A"]

        case .gsa:
            let gpsSignal = snapshot.gpsSignal
            let usedPRNs = gpsSignal.satellites
                .filter(\.isUsedInFix)
                .prefix(12)
                .map { String(format: "%02d", $0.prn) }
            let paddedPRNs = usedPRNs + Array(repeating: "", count: max(0, 12 - usedPRNs.count))
            return ["$\(talkerID)GSA,\(gpsSignal.selectionMode),\(gpsSignal.fixMode),\(paddedPRNs.joined(separator: ",")),\(String(format: "%.1f", gpsSignal.pdop)),\(String(format: "%.1f", gpsSignal.hdop)),\(String(format: "%.1f", gpsSignal.vdop))"]

        case .gsv:
            let satellites = snapshot.gpsSignal.satellites
            let totalMessages = Int(ceil(Double(satellites.count) / 4.0))
            return stride(from: 0, to: satellites.count, by: 4).enumerated().map { index, start in
                let chunk = satellites[start..<min(start + 4, satellites.count)]
                let fields = chunk.map { satellite in
                    "\(String(format: "%02d", satellite.prn)),\(satellite.elevation),\(satellite.azimuth),\(satellite.snr)"
                }
                return "$\(talkerID)GSV,\(totalMessages),\(index + 1),\(satellites.count),\(fields.joined(separator: ","))"
            }

        case .zda:
            let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: snapshot.timestamp)
            return ["$\(talkerID)ZDA,\(timeString),\(String(format: "%02d", components.day ?? 0)),\(String(format: "%02d", components.month ?? 0)),\(components.year ?? 0),00,00"]

        default:
            return []
        }
    }

    private func resolvedTrueHeading(in snapshot: SimulationSnapshot) -> Double? {
        if let gyroHeading = snapshot.gyroHeading {
            return normalizeAngle(gyroHeading)
        }

        guard let magneticHeading = snapshot.magneticHeading else {
            return nil
        }

        return normalizeAngle(magneticHeading + snapshot.magneticVariation)
    }

    private func normalizedMagneticCourse(fromTrue trueCourse: Double, variation: Double? = nil) -> Double {
        normalizeAngle(trueCourse - (variation ?? 0))
    }

    private func speedComponents(speedKnots: Double?, course: Double?, referenceHeading: Double) -> (longitudinal: Double?, transverse: Double?) {
        guard let speedKnots, let course else {
            return (nil, nil)
        }

        let relativeAngle = calculateShortestRotation(from: referenceHeading, to: course)
        let radians = toRadians(relativeAngle)
        return (speedKnots * cos(radians), speedKnots * sin(radians))
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

    func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }
}
