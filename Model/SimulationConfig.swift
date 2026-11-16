import Foundation

/// Read-only snapshot of user-facing configuration captured at the start of each simulation cycle.
///
/// The off-main transmit loop grabs one of these from the main thread at the top of every
/// cycle so it can read toggles, intervals, and modes without touching `@Observable` state.
struct SimulationConfig {
    let sensorToggles: SensorToggleStates
    let sentenceToggles: SentenceToggleStates
    let interval: Double
    let sentenceIntervals: [NMEASentenceType: TimeInterval]
    let weatherSourceMode: WeatherSourceMode
    let latestLiveWeather: LiveWeatherSnapshot?
    let boatSpeedMode: BoatSpeedMode
    let boatProfile: BoatProfile
    let waypointNavigation: WaypointNavigation
    let tackAnimationInProgress: Bool
    let maneuverSettings: ManeuverOperatorSettings
    let talkerID: String
    let perSentenceTalkerID: [NMEASentenceType: String]
    let depthOffsetMeters: Double
    let faultInjection: FaultInjectionSettings
    let mwvReferenceMode: MWVReferenceMode
    let enabledOutputEndpoints: [OutputEndpoint]
    let serialBaudRate: SerialBaudRate

    init(
        sensorToggles: SensorToggleStates,
        sentenceToggles: SentenceToggleStates,
        interval: Double,
        sentenceIntervals: [NMEASentenceType: TimeInterval],
        weatherSourceMode: WeatherSourceMode,
        latestLiveWeather: LiveWeatherSnapshot?,
        boatSpeedMode: BoatSpeedMode,
        boatProfile: BoatProfile,
        waypointNavigation: WaypointNavigation,
        tackAnimationInProgress: Bool,
        maneuverSettings: ManeuverOperatorSettings,
        talkerID: String,
        perSentenceTalkerID: [NMEASentenceType: String],
        depthOffsetMeters: Double,
        faultInjection: FaultInjectionSettings,
        mwvReferenceMode: MWVReferenceMode,
        enabledOutputEndpoints: [OutputEndpoint],
        serialBaudRate: SerialBaudRate = .unlimited
    ) {
        self.sensorToggles = sensorToggles
        self.sentenceToggles = sentenceToggles
        self.interval = interval
        self.sentenceIntervals = sentenceIntervals
        self.weatherSourceMode = weatherSourceMode
        self.latestLiveWeather = latestLiveWeather
        self.boatSpeedMode = boatSpeedMode
        self.boatProfile = boatProfile
        self.waypointNavigation = waypointNavigation
        self.tackAnimationInProgress = tackAnimationInProgress
        self.maneuverSettings = maneuverSettings
        self.talkerID = talkerID
        self.perSentenceTalkerID = perSentenceTalkerID
        self.depthOffsetMeters = depthOffsetMeters
        self.faultInjection = faultInjection
        self.mwvReferenceMode = mwvReferenceMode
        self.enabledOutputEndpoints = enabledOutputEndpoints
        self.serialBaudRate = serialBaudRate
    }

    /// A copy with the fields an in-memory experiment is allowed to select.
    /// The original config is left unchanged.
    func configuredForExperiment(
        weatherSourceMode: WeatherSourceMode,
        boatSpeedMode: BoatSpeedMode,
        boatProfile: BoatProfile
    ) -> SimulationConfig {
        SimulationConfig(
            sensorToggles: sensorToggles,
            sentenceToggles: sentenceToggles,
            interval: interval,
            sentenceIntervals: sentenceIntervals,
            weatherSourceMode: weatherSourceMode,
            latestLiveWeather: latestLiveWeather,
            boatSpeedMode: boatSpeedMode,
            boatProfile: boatProfile,
            waypointNavigation: waypointNavigation,
            tackAnimationInProgress: tackAnimationInProgress,
            maneuverSettings: maneuverSettings,
            talkerID: talkerID,
            perSentenceTalkerID: perSentenceTalkerID,
            depthOffsetMeters: depthOffsetMeters,
            faultInjection: faultInjection,
            mwvReferenceMode: mwvReferenceMode,
            enabledOutputEndpoints: enabledOutputEndpoints,
            serialBaudRate: serialBaudRate
        )
    }
}

/// Thread-safe snapshot of every `NMEASimulator` property the simulation queue reads.
///
/// Written under `inputMirrorLock` on the main thread (inside `persistSettingsIfNeeded`),
/// read under the same lock on the simulation queue at the top of each tick.
/// Because it is `@ObservationIgnored` and behind an `NSLock`, the `@Observable`
/// registrar is never touched from the simulation queue.
struct SimulationInputMirror {

    // MARK: - Sensor setpoints (used by syncLiveSetpointsIntoRuntime)

    var twd: SimulatedValue
    var tws: SimulatedValue
    var speed: SimulatedValue
    var depth: SimulatedValue
    var seaTemp: SimulatedValue
    var airTemp: SimulatedValue
    var humidity: SimulatedValue
    var barometer: SimulatedValue
    var heading: SimulatedValue
    var gyroHeading: SimulatedValue
    var gpsData: GPSData
    var isEditingGPSCoordinates: Bool
    var gpsCoordinateSetpointGeneration: UInt64

    // MARK: - Config values (used by captureSimulationConfig)

    var sensorToggles: SensorToggleStates
    var sentenceToggles: SentenceToggleStates
    var interval: Double
    var sentenceIntervals: [NMEASentenceType: TimeInterval]
    var weatherSourceMode: WeatherSourceMode
    var latestLiveWeather: LiveWeatherSnapshot?
    var boatSpeedMode: BoatSpeedMode
    var boatProfile: BoatProfile
    var waypointNavigation: WaypointNavigation
    var tackAnimationInProgress: Bool
    var maneuverSettings: ManeuverOperatorSettings
    var talkerID: String
    var perSentenceTalkerID: [NMEASentenceType: String]
    var depthOffsetMeters: Double
    var faultInjection: FaultInjectionSettings
    var mwvReferenceMode: MWVReferenceMode
    var outputEndpoints: [OutputEndpoint]
    var serialBaudRate: SerialBaudRate
    var sailConfiguration: SailConfiguration

    init(from sim: NMEASimulator) {
        twd = sim.twd
        tws = sim.tws
        speed = sim.speed
        depth = sim.depth
        seaTemp = sim.seaTemp
        airTemp = sim.airTemp
        humidity = sim.humidity
        barometer = sim.barometer
        heading = sim.heading
        gyroHeading = sim.gyroHeading
        gpsData = sim.gpsData
        isEditingGPSCoordinates = sim.isEditingGPSCoordinates
        gpsCoordinateSetpointGeneration = sim.gpsCoordinateSetpointGeneration
        sensorToggles = sim.sensorToggles
        sentenceToggles = sim.sentenceToggles
        interval = sim.interval
        sentenceIntervals = sim.sentenceIntervals
        weatherSourceMode = sim.weatherSourceMode
        latestLiveWeather = sim.latestLiveWeather
        boatSpeedMode = sim.boatSpeedMode
        boatProfile = sim.boatProfile
        waypointNavigation = sim.waypointNavigation
        tackAnimationInProgress = sim.tackAnimationInProgress
        maneuverSettings = sim.maneuverSettings
        talkerID = sim.talkerID
        perSentenceTalkerID = sim.perSentenceTalkerID
        depthOffsetMeters = sim.depthOffsetMeters
        faultInjection = sim.faultInjection
        mwvReferenceMode = sim.mwvReferenceMode
        outputEndpoints = sim.outputEndpoints
        serialBaudRate = sim.serialBaudRate
        sailConfiguration = sim.sailConfiguration
    }
}
