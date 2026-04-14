//
//  NMEANumericFormatting.swift
//  NMEASimulator
//
//  Locale-stable numeric formatting for NMEA 0183 payloads. Receivers expect ASCII '.' as the
//  decimal separator regardless of the user's macOS region (e.g. comma-decimal locales).
//

import Foundation

enum NMEANumericFormatting {

    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let lock = NSLock()
    private static var formatters: [Int: NumberFormatter] = [:]

    private static func decimalFormatter(fractionDigits: Int) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }

        if let cached = formatters[fractionDigits] {
            return cached
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumIntegerDigits = 1
        formatter.usesGroupingSeparator = false
        formatters[fractionDigits] = formatter
        return formatter
    }

    static func format(_ value: Double, fractionDigits: Int) -> String {
        decimalFormatter(fractionDigits: fractionDigits).string(from: NSNumber(value: value))
            ?? String(describing: value)
    }

    static func formatOptional(_ value: Double?, fractionDigits: Int) -> String {
        guard let value else { return "" }
        return format(value, fractionDigits: fractionDigits)
    }

    /// Minutes fragment for NMEA latitude/longitude (`ddmm.mmmm` / `dddmm.mmmm` bodies): two integer digits, four fraction digits, ASCII `.`.
    static func formatCoordinateMinutes(_ minutes: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        formatter.minimumIntegerDigits = 2
        formatter.maximumIntegerDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: minutes)) ?? format(minutes, fractionDigits: 4)
    }
}
