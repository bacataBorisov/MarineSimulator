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
                return ["$\(talkerID)MWV,\(NMEANumericFormatting.format(awa, fractionDigits: 0)),R,\(NMEANumericFormatting.format(aws, fractionDigits: 1)),N,A"]
            }

            guard let twa = computeTWA(from: snapshot), let tws = computeTWS(from: snapshot) else { return [] }
            return ["$\(talkerID)MWV,\(NMEANumericFormatting.format(twa, fractionDigits: 0)),T,\(NMEANumericFormatting.format(tws, fractionDigits: 1)),N,A"]

        case .mwd:
            guard let twd = computeTWD(from: snapshot), let tws = computeTWS(from: snapshot) else { return [] }
            let magneticDirection = normalizeAngle(twd - snapshot.magneticVariation)
            let twsMS = tws * 0.514444
            return ["$\(talkerID)MWD,\(NMEANumericFormatting.format(twd, fractionDigits: 1)),T,\(NMEANumericFormatting.format(magneticDirection, fractionDigits: 1)),M,\(NMEANumericFormatting.format(tws, fractionDigits: 1)),N,\(NMEANumericFormatting.format(twsMS, fractionDigits: 1)),M"]

        case .vpw:
            guard let vpwKnots = computeVPWKnots(from: snapshot), let vpwMS = computeVPWMS(from: snapshot) else { return [] }
            return ["$\(talkerID)VPW,\(NMEANumericFormatting.format(vpwKnots, fractionDigits: 1)),N,\(NMEANumericFormatting.format(vpwMS, fractionDigits: 1)),M"]

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

        return ["$\(talkerID)HDG,\(NMEANumericFormatting.format(headingMag, fractionDigits: 1)),\(NMEANumericFormatting.format(deviationDeg, fractionDigits: 1)),\(deviationHemisphere),\(NMEANumericFormatting.format(variationDeg, fractionDigits: 1)),\(variationHemisphere)"]
    }

    private func buildGyroSentences(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) -> [String] {
        switch type {
        case .hdt:
            guard let headingTrue = resolvedTrueHeading(in: snapshot) else {
                return []
            }
            return ["$\(talkerID)HDT,\(NMEANumericFormatting.format(headingTrue, fractionDigits: 1)),T"]

        case .rot:
            let status = abs(snapshot.turnRate) < 0.01 ? "V" : "A"
            return ["$\(talkerID)ROT,\(NMEANumericFormatting.format(snapshot.turnRate, fractionDigits: 1)),\(status)"]

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
            return ["$\(talkerID)DBT,\(NMEANumericFormatting.format(depthFeet, fractionDigits: 1)),f,\(NMEANumericFormatting.format(depthMeters, fractionDigits: 1)),M,\(NMEANumericFormatting.format(depthFathoms, fractionDigits: 1)),F"]

        case .dpt:
            guard let depthMeters = snapshot.depth else { return [] }
            return ["$\(talkerID)DPT,\(NMEANumericFormatting.format(depthMeters, fractionDigits: 1)),\(NMEANumericFormatting.format(depthOffsetMeters, fractionDigits: 1))"]

        case .mtw:
            guard let seaTemperature = snapshot.seaTemperature else { return [] }
            return ["$\(talkerID)MTW,\(NMEANumericFormatting.format(seaTemperature, fractionDigits: 1)),C"]

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
            return ["$\(talkerID)VLW,\(NMEANumericFormatting.format(snapshot.logDistanceNm, fractionDigits: 2)),N,\(NMEANumericFormatting.format(snapshot.tripDistanceNm, fractionDigits: 2)),N"]

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
        let cogString = NMEANumericFormatting.format(snapshot.gpsData.courseOverGround, fractionDigits: 1)
        let sogString = NMEANumericFormatting.format(snapshot.gpsData.speedOverGround, fractionDigits: 1)

        switch type {
        case .rmc:
            let variation = abs(snapshot.magneticVariation)
            let variationHemisphere = snapshot.magneticVariation >= 0 ? "E" : "W"
            return ["$\(talkerID)RMC,\(timeString),A,\(latString),\(lonString),\(sogString),\(cogString),\(dateString),\(NMEANumericFormatting.format(variation, fractionDigits: 1)),\(variationHemisphere),A"]

        case .gga:
            let gpsSignal = snapshot.gpsSignal
            return ["$\(talkerID)GGA,\(timeString),\(latString),\(lonString),\(gpsSignal.fixQuality),\(String(format: "%02d", gpsSignal.satellitesUsed)),\(NMEANumericFormatting.format(gpsSignal.hdop, fractionDigits: 1)),\(NMEANumericFormatting.format(gpsSignal.altitudeMeters, fractionDigits: 1)),M,\(NMEANumericFormatting.format(gpsSignal.geoidalSeparationMeters, fractionDigits: 1)),M,,"]

        case .vtg:
            let magneticCourse = normalizedMagneticCourse(fromTrue: snapshot.gpsData.courseOverGround, variation: snapshot.magneticVariation)
            let sogKmh = snapshot.gpsData.speedOverGround * 1.852
            return ["$\(talkerID)VTG,\(cogString),T,\(NMEANumericFormatting.format(magneticCourse, fractionDigits: 1)),M,\(sogString),N,\(NMEANumericFormatting.format(sogKmh, fractionDigits: 1)),K,A"]

        case .gll:
            return ["$\(talkerID)GLL,\(latString),\(lonString),\(timeString),A,A"]

        case .gsa:
            let gpsSignal = snapshot.gpsSignal
            let usedPRNs = gpsSignal.satellites
                .filter(\.isUsedInFix)
                .prefix(12)
                .map { String(format: "%02d", $0.prn) }
            let paddedPRNs = usedPRNs + Array(repeating: "", count: max(0, 12 - usedPRNs.count))
            return ["$\(talkerID)GSA,\(gpsSignal.selectionMode),\(gpsSignal.fixMode),\(paddedPRNs.joined(separator: ",")),\(NMEANumericFormatting.format(gpsSignal.pdop, fractionDigits: 1)),\(NMEANumericFormatting.format(gpsSignal.hdop, fractionDigits: 1)),\(NMEANumericFormatting.format(gpsSignal.vdop, fractionDigits: 1))"]

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
        NMEANumericFormatting.formatOptional(value, fractionDigits: decimals)
    }

    func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }
}
