import Foundation

/// Enum to represent different types of navigational metrics
enum SimulatedValueType: String, CaseIterable, Codable, Identifiable {
    case magneticCompass
    case gyroCompass
    case windDirection
    case windSpeed
    case speedLog
    case speedOverGround
    case depth
    case seaTemp
    case airTemp
    case humidity
    case barometer

    /// Required for Identifiable conformance
    var id: String { rawValue }

    /// Human-readable label for UI
    var displayName: String {
        switch self {
        case .magneticCompass: return "Magnetic Heading"
        case .gyroCompass: return "Gyro Heading"
        case .windDirection: return "Wind Direction"
        case .windSpeed: return "Wind Speed"
        case .speedLog: return "Speed Log"
        case .speedOverGround: return "Speed Over Ground"
        case .depth: return "Depth"
        case .seaTemp: return "Sea Temp"
        case .airTemp: return "Air Temp"
        case .humidity: return "Humidity"
        case .barometer: return "Barometer"
        }
    }

    /// Default range for each metric
    var defaultRange: ClosedRange<Double> {
        switch self {
        case .magneticCompass, .windDirection:
            return 0...359
        case .windSpeed, .speedLog, .speedOverGround:
            return 0...50
        case .depth:
            return 0...1000
        case .seaTemp:
            return 0...40
        case .airTemp:
            return -20...50
        case .humidity:
            return 0...100
        case .barometer:
            return 960...1050
        case .gyroCompass:
            return 0...359.9
        }
    }

    /// Default offset to be used in random generation
    var defaultOffset: Double {
        switch self {
        case .magneticCompass, .gyroCompass, .windDirection:
            return 10
        case .windSpeed, .speedLog, .speedOverGround:
            return 3
        case .depth:
            return 20
        case .seaTemp:
            return 3
        case .airTemp:
            return 4
        case .humidity:
            return 8
        case .barometer:
            return 6
        }
    }
}

/// Struct to represent a metric with optional value and random generation
struct SimulatedValue: Codable, Equatable {
    var value: Double?
    var range: ClosedRange<Double>
    var centerValue: Double
    var offset: Double

    /// Initializes a metric using a MetricType and optional overrides
    init(
        type: SimulatedValueType,
        center: Double? = nil,
        offset: Double? = nil,
        value: Double? = nil
    ) {
        self.range = type.defaultRange
        self.centerValue = center ?? (range.lowerBound + range.upperBound) / 2
        self.offset = offset ?? type.defaultOffset
        self.value = value
    }

    /// The lower bound used during random value generation
    var lowerBound: Double {
        max(range.lowerBound, centerValue - offset)
    }

    /// The upper bound used during random value generation
    var upperBound: Double {
        min(range.upperBound, centerValue + offset)
    }

    /// Generates a new random value within the center ± offset range
    mutating func generateRandomValue(shouldGenerate: Bool = true) -> Double? {
        guard shouldGenerate else {
            value = nil
            return nil
        }

        // Ensure the center value is within allowed range
        centerValue = centerValue.clamped(to: range)

        // Limit offset so it never exceeds half of total range
        let maxAllowedOffset = (range.upperBound - range.lowerBound) / 2
        offset = min(offset, maxAllowedOffset)

        let generated = Double.random(in: lowerBound...upperBound)
        value = generated
        return generated
    }
}

/// Extension to safely clamp values within a range
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
