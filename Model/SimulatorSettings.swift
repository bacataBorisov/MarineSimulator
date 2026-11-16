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
    var airTemp: SimulatedValue
    var humidity: SimulatedValue
    var barometer: SimulatedValue
    var heading: SimulatedValue
    var gyroHeading: SimulatedValue
    var gpsData: GPSData
    var faultInjection: FaultInjectionSettings
    var mwvReferenceMode: MWVReferenceMode
    var selectedPreset: SimulationPreset?
    var selectedProfile: HardwareProfile
    var sentenceRateMode: SentenceRateMode
    var serialBaudRate: SerialBaudRate
    var fragmentTCPStream: Bool
    var perSentenceTalkerID: [String: String]
    var boatProfile: BoatProfile
    var boatSpeedMode: BoatSpeedMode
    var weatherSourceMode: WeatherSourceMode
    var liveWeatherSettings: LiveWeatherSettings
    var latestLiveWeather: LiveWeatherSnapshot?
    var waypointNavigation: WaypointNavigation
    var maneuverSettings: ManeuverOperatorSettings
    /// Persisted vessel identity. Absent means no selection has been stored.
    var activeVesselID: String?
    /// True when `activeVesselID` or a legacy vessel name was present in saved settings.
    var vesselSelectionWasStored: Bool

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
        case airTemp
        case humidity
        case barometer
        case heading
        case gyroHeading
        case gpsData
        case faultInjection
        case mwvReferenceMode
        case selectedPreset
        case selectedProfile
        case sentenceRateMode
        case serialBaudRate
        case fragmentTCPStream
        case perSentenceTalkerID
        case boatProfile
        case boatSpeedMode
        case weatherSourceMode
        case liveWeatherSettings
        case latestLiveWeather
        case waypointNavigation
        case maneuverSettings
        case activeVesselID
        case vesselSelectionWasStored
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
        airTemp: SimulatedValue,
        humidity: SimulatedValue,
        barometer: SimulatedValue,
        heading: SimulatedValue,
        gyroHeading: SimulatedValue,
        gpsData: GPSData,
        faultInjection: FaultInjectionSettings,
        mwvReferenceMode: MWVReferenceMode,
        selectedPreset: SimulationPreset?,
        selectedProfile: HardwareProfile = .bngTriton2,
        sentenceRateMode: SentenceRateMode = .realistic,
        serialBaudRate: SerialBaudRate = .unlimited,
        fragmentTCPStream: Bool = false,
        perSentenceTalkerID: [String: String] = [:],
        boatProfile: BoatProfile,
        boatSpeedMode: BoatSpeedMode,
        weatherSourceMode: WeatherSourceMode,
        liveWeatherSettings: LiveWeatherSettings,
        latestLiveWeather: LiveWeatherSnapshot?,
        waypointNavigation: WaypointNavigation = WaypointNavigation(),
        maneuverSettings: ManeuverOperatorSettings = ManeuverOperatorSettings(),
        activeVesselID: String? = nil,
        vesselSelectionWasStored: Bool = false
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
        self.airTemp = airTemp
        self.humidity = humidity
        self.barometer = barometer
        self.heading = heading
        self.gyroHeading = gyroHeading
        self.gpsData = gpsData
        self.faultInjection = faultInjection
        self.mwvReferenceMode = mwvReferenceMode
        self.selectedPreset = selectedPreset
        self.selectedProfile = selectedProfile
        self.sentenceRateMode = sentenceRateMode
        self.serialBaudRate = serialBaudRate
        self.fragmentTCPStream = fragmentTCPStream
        self.perSentenceTalkerID = perSentenceTalkerID
        self.boatProfile = boatProfile
        self.boatSpeedMode = boatSpeedMode
        self.weatherSourceMode = weatherSourceMode
        self.liveWeatherSettings = liveWeatherSettings
        self.latestLiveWeather = latestLiveWeather
        self.waypointNavigation = waypointNavigation
        self.maneuverSettings = maneuverSettings
        self.activeVesselID = activeVesselID
        self.vesselSelectionWasStored = vesselSelectionWasStored
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
        depthOffsetMeters = try container.decodeIfPresent(Double.self, forKey: .depthOffsetMeters) ?? 0.0
        seaTemp = try container.decode(SimulatedValue.self, forKey: .seaTemp)
        airTemp = try container.decodeIfPresent(SimulatedValue.self, forKey: .airTemp) ?? SimulatedValue(type: .airTemp)
        humidity = try container.decodeIfPresent(SimulatedValue.self, forKey: .humidity) ?? SimulatedValue(type: .humidity)
        barometer = try container.decodeIfPresent(SimulatedValue.self, forKey: .barometer) ?? SimulatedValue(type: .barometer)
        heading = try container.decode(SimulatedValue.self, forKey: .heading)
        gyroHeading = try container.decode(SimulatedValue.self, forKey: .gyroHeading)
        gpsData = try container.decode(GPSData.self, forKey: .gpsData)
        faultInjection = try container.decodeIfPresent(FaultInjectionSettings.self, forKey: .faultInjection) ?? FaultInjectionSettings()
        mwvReferenceMode = try container.decodeIfPresent(MWVReferenceMode.self, forKey: .mwvReferenceMode) ?? .relative
        selectedPreset = try container.decodeIfPresent(SimulationPreset.self, forKey: .selectedPreset)
        selectedProfile = try container.decodeIfPresent(HardwareProfile.self, forKey: .selectedProfile) ?? .bngTriton2
        sentenceRateMode = try container.decodeIfPresent(SentenceRateMode.self, forKey: .sentenceRateMode) ?? .realistic
        serialBaudRate = try container.decodeIfPresent(SerialBaudRate.self, forKey: .serialBaudRate) ?? .unlimited
        fragmentTCPStream = try container.decodeIfPresent(Bool.self, forKey: .fragmentTCPStream) ?? false
        perSentenceTalkerID = try container.decodeIfPresent([String: String].self, forKey: .perSentenceTalkerID) ?? [:]
        if container.contains(.activeVesselID) {
            activeVesselID = try container.decodeIfPresent(String.self, forKey: .activeVesselID) ?? ""
            vesselSelectionWasStored = true
            if let known = BoatProfile(rawValue: try container.decodeIfPresent(String.self, forKey: .boatProfile) ?? "") {
                boatProfile = known
            } else {
                boatProfile = .beneteauFirst407
            }
        } else if container.contains(.boatProfile) {
            let raw = try container.decode(String.self, forKey: .boatProfile)
            if let known = BoatProfile(rawValue: raw) {
                boatProfile = known
                activeVesselID = (known == .nimana ? BuiltInVesselID.nimana : BuiltInVesselID.extasy).uuidString
            } else {
                boatProfile = .nimana
                activeVesselID = raw
            }
            vesselSelectionWasStored = true
        } else {
            boatProfile = .beneteauFirst407
            activeVesselID = nil
            vesselSelectionWasStored = false
        }
        boatSpeedMode = try container.decodeIfPresent(BoatSpeedMode.self, forKey: .boatSpeedMode) ?? .manual
        weatherSourceMode = try container.decodeIfPresent(WeatherSourceMode.self, forKey: .weatherSourceMode) ?? .manual
        liveWeatherSettings = try container.decodeIfPresent(LiveWeatherSettings.self, forKey: .liveWeatherSettings) ?? LiveWeatherSettings()
        latestLiveWeather = try container.decodeIfPresent(LiveWeatherSnapshot.self, forKey: .latestLiveWeather)
        waypointNavigation = try container.decodeIfPresent(WaypointNavigation.self, forKey: .waypointNavigation) ?? WaypointNavigation()
        maneuverSettings = try container.decodeIfPresent(ManeuverOperatorSettings.self, forKey: .maneuverSettings) ?? ManeuverOperatorSettings()
    }
}
