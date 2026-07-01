import Foundation

enum HardwareProfile: String, CaseIterable, Codable, Identifiable {
    case bngTriton2 = "B&G Triton 2"
    case furunoFI70 = "Furuno FI-70"
    case garminGMI20 = "Garmin GMI 20"
    case yachtDevicesGateway = "Yacht Devices YDNG-03"
    case minimalGPS = "GPS Only"
    case custom = "Custom"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .bngTriton2:
            return "Full instrument suite with 10 Hz compass/gyro and multi-talker IDs."
        case .furunoFI70:
            return "Fluxgate compass only — no gyro — with standard 1 Hz sensor rates."
        case .garminGMI20:
            return "Garmin instrument cluster: GP talker, no GLL sentence."
        case .yachtDevicesGateway:
            return "Multiplexed gateway: 10 Hz HDG, 5 Hz GPS core sentences."
        case .minimalGPS:
            return "Standalone GPS receiver — position sentences only."
        case .custom:
            return "Keep current sensor, sentence, rate, and talker configuration."
        }
    }
}

enum SentenceRateMode: String, Codable, CaseIterable, Identifiable {
    case realistic
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realistic:
            return "Realistic"
        case .custom:
            return "Custom"
        }
    }
}
