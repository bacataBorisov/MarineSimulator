//
//  FormatKit.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 11.06.25.
//

import Foundation
import SwiftUI

enum FormatKit {
    
    static let plainNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.usesGroupingSeparator = false // Disable thousands separator
        formatter.numberStyle = .decimal         // Regular decimal numbers
        return formatter
    }()
    
    static func decimalFormatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = fractionDigits
        formatter.minimumIntegerDigits = 1
        formatter.decimalSeparator = "."  // 🔥 Always use dot
        return formatter
    }
    
    static func formattedValue(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "--" }
        return String(format: "%.*f", decimals, value)
    }
    
    static func formatLatitude(_ latitude: Double) -> String {
        let hemisphere = latitude >= 0 ? "N" : "S"
        let absLat = abs(latitude)
        let degrees = Int(absLat)
        let minutes = (absLat - Double(degrees)) * 60
        return String(format: "%02d%07.4f,%@", degrees, minutes, hemisphere)
    }

    static func formatLongitude(_ longitude: Double) -> String {
        let hemisphere = longitude >= 0 ? "E" : "W"
        let absLon = abs(longitude)
        let degrees = Int(absLon)
        let minutes = (absLon - Double(degrees)) * 60
        return String(format: "%03d%07.4f,%@", degrees, minutes, hemisphere)
    }
}
