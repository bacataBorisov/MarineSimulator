//
//  NMEASimulator+SentenceBuilder.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 13.06.25.
//

import Foundation

extension NMEASimulator {

    enum NMEASentenceType {
        case speed, depth, temp
        case trueWind, apparentWind
        case gps
        case mwd             // Wind Direction and Speed
        case vpw             // Speed measured parallel to Wind
        case hdg             // Heading, Deviation & Variation
        case hdt             // Heading True
        case rot             // Rate of Turn
    }

    var turnRate: Double {
        Double.random(in: -3.0...3.0) // ±3°/min typical for simulation
    }
    
    func buildNMEASentence(talkerID: String, type: NMEASentenceType) -> String {
        generateRandomValues()

        let sentence: String = {
            switch type {
            case .trueWind, .apparentWind:
                return buildWindSentence(talkerID: talkerID, type: type)
            case .hdg:
                return buildCompassSentence(talkerID: talkerID)
            case .speed, .depth, .temp:
                return buildHydroSentence(talkerID: talkerID, type: type)
            case .gps:
                return buildGPSSentence(talkerID: talkerID)
            case .mwd, .vpw:
                return buildWindSentence(talkerID: talkerID, type: type)
            case .hdt, .rot:
                return buildGyroSentence(talkerID: talkerID, type: type)
            }
        }()

        return addChecksum(to: sentence)
    }

    private func buildWindSentence(talkerID: String, type: NMEASentenceType) -> String {
        switch type {
        case .trueWind:
            guard let twa = calculatedTWA, let tws = calculatedTWS else { return "" }
            return "$\(talkerID)MWV,\(String(format: "%.0f", twa)),T,\(String(format: "%.1f", tws)),N,A"

        case .apparentWind:
            guard let awa = calculatedAWA, let aws = calculatedAWS else { return "" }
            return "$\(talkerID)MWV,\(String(format: "%.0f", awa)),R,\(String(format: "%.1f", aws)),N,A"

        case .mwd:
            guard let twd = calculatedTWD, let tws = calculatedTWS else { return "" }
            return "$\(talkerID)MWD,\(String(format: "%.1f", twd)),T,,M,\(String(format: "%.1f", tws)),N,,M"

        case .vpw:
            guard let vpwKnots = calculatedVPWKnots, let vpwMS = calculatedVPWMS else { return "" }
            return "$\(talkerID)VPW,\(String(format: "%.1f", vpwKnots)),N,\(String(format: "%.1f", vpwMS)),M"

        default:
            return ""
        }
    }

    private func buildCompassSentence(talkerID: String) -> String {
        let headingMag = heading.value ?? 0.0

        // Simulated deviation and variation values
        let deviationDeg = 2.0
        let deviationDir = "E" // or "W"

        let variationDeg = 3.0
        let variationDir = "W" // or "E"

        let headingString = String(format: "%.f", headingMag)
        
        //TODO: - This need to be included in the UI later, so be adjusted
        let deviationString = String(format: "%.f", deviationDeg)
        let variationString = String(format: "%.f", variationDeg)

        return "$\(talkerID)HDG,\(headingString),\(deviationString),\(deviationDir),\(variationString),\(variationDir)"
    }
    private func buildGyroSentence(talkerID: String, type: NMEASentenceType) -> String {
        switch type {

        case .hdt:
            let headingTrue = heading.value ?? 0
            return "$\(talkerID)HDT,\(String(format: "%.1f", headingTrue)),T" //assume .1 precision

        case .rot:
            let rateOfTurn = turnRate // Assume this is in degrees/minute
            let status = rateOfTurn == 0 ? "V" : "A"
            return "$\(talkerID)ROT,\(String(format: "%.1f", rateOfTurn)),\(status)" //assume .1 precision

        default:
            return ""
        }
    }

    private func buildHydroSentence(talkerID: String, type: NMEASentenceType) -> String {
        switch type {
        case .speed:
            return "$\(talkerID)VHW,,T,,M,\(String(format: "%.1f", speed.value ?? 0)),N,,K"
        case .depth:
            return "$\(talkerID)DPT,\(String(format: "%.1f", depth.value ?? 0)),0.0"
        case .temp:
            return "$\(talkerID)MTW,\(String(format: "%.1f", seaTemp.value ?? 0)),C"
        default:
            return ""
        }
    }

    private func buildGPSSentence(talkerID: String) -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss.SS"
        let timeString = formatter.string(from: now)

        formatter.dateFormat = "ddMMyy"
        let dateString = formatter.string(from: now)

        let latString = FormatKit.formatLatitude(gps.latitude)
        let lonString = FormatKit.formatLongitude(gps.longitude)

        let cogString = String(format: "%.1f", gps.courseOverGround)
        let sogString = String(format: "%.1f", gps.speedOverGround)

        return "$\(talkerID)RMC,\(timeString),A,\(latString),\(lonString),\(sogString),\(cogString),\(dateString),,,A"
    }

    private func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }
}
