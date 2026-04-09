import Foundation

struct FaultInjectionSettings: Codable {
    var isEnabled: Bool = false
    var dropRate: Double = 0
    var delayRate: Double = 0
    var checksumCorruptionRate: Double = 0
    var invalidDataRate: Double = 0
    var maximumDelayCycles: Int = 2
}

enum MWVReferenceMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case relative
    case trueReference = "true"

    var id: String { rawValue }
}

enum SimulationPreset: String, Codable, CaseIterable, Identifiable {
    case harborCalm
    case lightWeather
    case stormyWeather

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .harborCalm:
            return "Harbor Calm"
        case .lightWeather:
            return "Light Weather"
        case .stormyWeather:
            return "Stormy Weather"
        }
    }

    var summary: String {
        switch self {
        case .harborCalm:
            return "Stable boat and low wind for baseline receiver checks."
        case .lightWeather:
            return "Moderate wind and motion for day-to-day interoperability testing."
        case .stormyWeather:
            return "Higher wind, variation, and motion for stress testing receivers."
        }
    }
}

struct SimulatorSettings: Codable {
    var ip: String
    var port: UInt16
    var talkerID: String
    var outputEndpoints: [OutputEndpoint]
    var sentenceIntervals: [String: Double]
    var isTimerSelected: Bool
    var interval: Double
    var sentenceToggles: SentenceToggleStates
    var sensorToggles: SensorToggleStates
    var twd: SimulatedValue
    var tws: SimulatedValue
    var speed: SimulatedValue
    var depth: SimulatedValue
    var depthOffsetMeters: Double
    var seaTemp: SimulatedValue
    var heading: SimulatedValue
    var gyroHeading: SimulatedValue
    var gpsData: GPSData
    var faultInjection: FaultInjectionSettings
    var mwvReferenceMode: MWVReferenceMode
    var selectedPreset: SimulationPreset?

    private enum CodingKeys: String, CodingKey {
        case ip
        case port
        case talkerID
        case outputEndpoints
        case sentenceIntervals
        case isTimerSelected
        case interval
        case sentenceToggles
        case sensorToggles
        case twd
        case tws
        case speed
        case depth
        case depthOffsetMeters
        case seaTemp
        case heading
        case gyroHeading
        case gpsData
        case faultInjection
        case mwvReferenceMode
        case selectedPreset
    }

    init(
        ip: String,
        port: UInt16,
        talkerID: String,
        outputEndpoints: [OutputEndpoint],
        sentenceIntervals: [String: Double],
        isTimerSelected: Bool,
        interval: Double,
        sentenceToggles: SentenceToggleStates,
        sensorToggles: SensorToggleStates,
        twd: SimulatedValue,
        tws: SimulatedValue,
        speed: SimulatedValue,
        depth: SimulatedValue,
        depthOffsetMeters: Double,
        seaTemp: SimulatedValue,
        heading: SimulatedValue,
        gyroHeading: SimulatedValue,
        gpsData: GPSData,
        faultInjection: FaultInjectionSettings,
        mwvReferenceMode: MWVReferenceMode,
        selectedPreset: SimulationPreset?
    ) {
        self.ip = ip
        self.port = port
        self.talkerID = talkerID
        self.outputEndpoints = outputEndpoints
        self.sentenceIntervals = sentenceIntervals
        self.isTimerSelected = isTimerSelected
        self.interval = interval
        self.sentenceToggles = sentenceToggles
        self.sensorToggles = sensorToggles
        self.twd = twd
        self.tws = tws
        self.speed = speed
        self.depth = depth
        self.depthOffsetMeters = depthOffsetMeters
        self.seaTemp = seaTemp
        self.heading = heading
        self.gyroHeading = gyroHeading
        self.gpsData = gpsData
        self.faultInjection = faultInjection
        self.mwvReferenceMode = mwvReferenceMode
        self.selectedPreset = selectedPreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        ip = try container.decode(String.self, forKey: .ip)
        port = try container.decode(UInt16.self, forKey: .port)
        talkerID = try container.decode(String.self, forKey: .talkerID)
        outputEndpoints = try container.decodeIfPresent([OutputEndpoint].self, forKey: .outputEndpoints)
            ?? [OutputEndpoint(host: ip, port: port)]
        sentenceIntervals = try container.decodeIfPresent([String: Double].self, forKey: .sentenceIntervals) ?? [:]
        isTimerSelected = try container.decode(Bool.self, forKey: .isTimerSelected)
        interval = try container.decode(Double.self, forKey: .interval)
        sentenceToggles = try container.decode(SentenceToggleStates.self, forKey: .sentenceToggles)
        sensorToggles = try container.decode(SensorToggleStates.self, forKey: .sensorToggles)
        twd = try container.decode(SimulatedValue.self, forKey: .twd)
        tws = try container.decode(SimulatedValue.self, forKey: .tws)
        speed = try container.decode(SimulatedValue.self, forKey: .speed)
        depth = try container.decode(SimulatedValue.self, forKey: .depth)
        depthOffsetMeters = try container.decode(Double.self, forKey: .depthOffsetMeters)
        seaTemp = try container.decode(SimulatedValue.self, forKey: .seaTemp)
        heading = try container.decode(SimulatedValue.self, forKey: .heading)
        gyroHeading = try container.decode(SimulatedValue.self, forKey: .gyroHeading)
        gpsData = try container.decode(GPSData.self, forKey: .gpsData)
        faultInjection = try container.decodeIfPresent(FaultInjectionSettings.self, forKey: .faultInjection) ?? FaultInjectionSettings()
        mwvReferenceMode = try container.decodeIfPresent(MWVReferenceMode.self, forKey: .mwvReferenceMode) ?? .relative
        selectedPreset = try container.decodeIfPresent(SimulationPreset.self, forKey: .selectedPreset)
    }
}
