import Foundation
import Observation

@Observable
class NMEASimulator {

    /// Same interval as `scheduleTackTimer` (60 Hz). UI can use short linear motion aligned to tack steps.
    static let tackAnimationTickInterval: TimeInterval = 1.0 / 60.0

    /// Internal scheduler cadence while transmitting; decoupled from the user-facing Send Interval.
    static let simulationFastTickInterval: TimeInterval = 0.05

    /// UI publish cadence. Engine stays at `simulationFastTickInterval`; views paint at this rate.
    static let displayPublishInterval: TimeInterval = 0.1
    /// Throttle console / stats `@Observable` churn while transmitting (see `recordOutputMessage`).
    static let consoleDisplayFlushInterval: TimeInterval = 0.1
    /// Bounded console history. Larger windows (e.g. 5 min / 2k rows) made SwiftUI rebuild
    /// thousands of LazyVStack rows every flush and progressively starved slider input.
    private static let consoleRetentionInterval: TimeInterval = 60
    private static let consoleMaxRecords = 400

    private static let simulationValuePersistDebounceInterval: TimeInterval = 5.0

    /// Posted on the main thread after each tack heading update (see `applySimulatedTrueHeading`). Wind/compass use this instead of SwiftUI `onChange` so 60 Hz steps are not coalesced or deferred.
    static let tackInstrumentStepNotification = Notification.Name("MarineSimulator.NMEASimulator.tackInstrumentStep")

    // SimulationState and PendingTransmission are defined in Model/SimulationState.swift
    // SimulationConfig is defined in Model/SimulationConfig.swift

    @ObservationIgnored private let persistenceManager: PersistenceManager
    @ObservationIgnored let weatherService: any WeatherService

    // MARK: - Sensors & Sentences States

    var sentenceToggles = SentenceToggleStates() {
        didSet { persistSettingsIfNeeded() }
    }
    var sensorToggles = SensorToggleStates() {
        didSet { persistSettingsIfNeeded() }
    }

    // MARK: - Network & Connectivity

    var ip: String = "127.0.0.1" {
        didSet {
            guard oldValue != ip else { return }
            syncPrimaryOutputEndpoint()
            resetTransportConnectionsIfTransmitting()
            persistSettingsIfNeeded()
        }
    }
    var isBroadcast: Bool = false {
        didSet {
            guard oldValue != isBroadcast else { return }
            syncPrimaryOutputEndpoint()
            resetTransportConnectionsIfTransmitting()
            persistSettingsIfNeeded()
        }
    }
    var port: UInt16 = 4950 {
        didSet {
            guard oldValue != port else { return }
            syncPrimaryOutputEndpoint()
            resetTransportConnectionsIfTransmitting()
            persistSettingsIfNeeded()
        }
    }
    var talkerID: String = "II" {
        didSet { persistSettingsIfNeeded() }
    }
    var outputEndpoints: [OutputEndpoint] = [
        OutputEndpoint(host: "127.0.0.1", port: 4950)
    ] {
        didSet {
            resetTransportConnectionsIfEndpointTargetsChanged(from: oldValue, to: outputEndpoints)
            normalizeOutputEndpoints()
            persistSettingsIfNeeded()
        }
    }

    @ObservationIgnored let transportManager = TransportManager()
    @ObservationIgnored let simulationQueue = DispatchQueue(label: "com.marinesimulator.simulation", qos: .userInitiated)
    static let simulationQueueMarker = DispatchSpecificKey<UInt8>()
    @ObservationIgnored var simulationTimer: DispatchSourceTimer?

    /// Lock-protected mirror of every property the simulation queue reads.
    /// Written on main (via `syncInputMirror`), read on the sim queue (via `readInputMirror`).
    @ObservationIgnored private let inputMirrorLock = NSLock()
    @ObservationIgnored private var inputMirror: SimulationInputMirror?

    var isTimerSelected = true {
        didSet {
            handleTimerSelectionChange()
            persistSettingsIfNeeded()
        }
    }
    var interval: Double = 1.0 {
        didSet {
            if interval < 0.1 {
                interval = 0.1
                return
            }
            persistSettingsIfNeeded()
        }
    }

    // MARK: - Wind

    var twd = SimulatedValue(type: .windDirection) {
        didSet { persistSettingsIfNeeded() }
    }
    var tws = SimulatedValue(type: .windSpeed) {
        didSet { persistSettingsIfNeeded() }
    }

    // MARK: - Hydro

    var speed = SimulatedValue(type: .speedLog) {
        didSet { persistSettingsIfNeeded() }
    }
    var depth = SimulatedValue(type: .depth) {
        didSet { persistSettingsIfNeeded() }
    }
    var depthOffsetMeters: Double = 0.0 {
        didSet { persistSettingsIfNeeded() }
    }
    var seaTemp = SimulatedValue(type: .seaTemp) {
        didSet { persistSettingsIfNeeded() }
    }
    var airTemp = SimulatedValue(type: .airTemp) {
        didSet { persistSettingsIfNeeded() }
    }
    var humidity = SimulatedValue(type: .humidity) {
        didSet { persistSettingsIfNeeded() }
    }
    var barometer = SimulatedValue(type: .barometer) {
        didSet { persistSettingsIfNeeded() }
    }

    // MARK: - Compass

    var heading = SimulatedValue(type: .magneticCompass) {
        didSet { persistSettingsIfNeeded() }
    }
    var gyroHeading = SimulatedValue(type: .gyroCompass) {
        didSet { persistSettingsIfNeeded() }
    }

    // MARK: - GPS & Positioning

    var gpsData = GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90) {
        didSet { persistSettingsIfNeeded() }
    }
    /// True while a GPS lat/lon field is focused — dead-reckoning must not overwrite the draft.
    @ObservationIgnored var isEditingGPSCoordinates = false
    /// Bumped when the user sets lat/lon (map or field). Transmit copies that fix once.
    @ObservationIgnored var gpsCoordinateSetpointGeneration: UInt64 = 0

    func applyUserGPSCoordinates(latitude: Double, longitude: Double) {
        var next = gpsData
        next.latitude = latitude
        next.longitude = longitude
        guard next != gpsData else { return }
        gpsCoordinateSetpointGeneration &+= 1
        gpsData = next
    }
    var faultInjection = FaultInjectionSettings() {
        didSet { persistSettingsIfNeeded() }
    }
    var mwvReferenceMode: MWVReferenceMode = .relative {
        didSet { persistSettingsIfNeeded() }
    }
    var selectedPreset: SimulationPreset? {
        didSet { persistSettingsIfNeeded() }
    }
    var selectedProfile: HardwareProfile = .bngTriton2 {
        didSet { persistSettingsIfNeeded() }
    }
    var sentenceRateMode: SentenceRateMode = .realistic {
        didSet {
            if sentenceRateMode == .realistic, oldValue == .custom, !isApplyingHardwareProfile {
                let profile: HardwareProfile = selectedProfile == .custom ? .bngTriton2 : selectedProfile
                applyHardwareProfile(profile)
            }
            persistSettingsIfNeeded()
        }
    }
    var perSentenceTalkerID: [NMEASentenceType: String] = [:] {
        didSet { persistSettingsIfNeeded() }
    }
    var boatProfile: BoatProfile = .beneteauFirst407 {
        didSet {
            guard !isRestoringSettings, !isApplyingVesselSelection else { return }
            activeVesselState = .resolved(boatProfile == .beneteauFirst407 ? BuiltInVesselID.extasy : BuiltInVesselID.nimana)
            persistSettingsIfNeeded()
        }
    }
    var activeVesselState: ActiveVesselState = .resolved(BuiltInVesselID.extasy)
    @ObservationIgnored private(set) var vesselRepository: VesselProfileRepository!
    private(set) var vessels: [VesselProfile] = []
    var vesselStoreError: VesselProfileStoreError?
    @ObservationIgnored private var isApplyingVesselSelection = false
    var sailConfiguration = SailConfiguration()
    var vesselObservation = VesselObservation()
    var activeManeuver: ActiveManeuver?
    /// Set when a maneuver command is refused. Heading is left where it was.
    var maneuverRejectionReason: String?
    var maneuverSettings = ManeuverOperatorSettings() {
        didSet { persistSettingsIfNeeded() }
    }
    var boatSpeedMode: BoatSpeedMode = .manual {
        didSet { persistSettingsIfNeeded() }
    }
    var waypointNavigation = WaypointNavigation() {
        didSet { persistSettingsIfNeeded() }
    }
    var weatherSourceMode: WeatherSourceMode = .manual {
        didSet {
            guard !isRestoringSettings else { return }

            if weatherSourceMode == .manual {
                liveWeatherTask?.cancel()
                liveWeatherTask = nil
                liveWeatherStatus = .idle
                resetLiveWeatherWindNoiseState()
            } else {
                selectedPreset = nil
                latestLiveWeather = nil
                twd.value = nil
                tws.value = nil
                seaTemp.value = nil
                airTemp.value = nil
                humidity.value = nil
                barometer.value = nil
                refreshLiveWeather(force: true)
            }
            persistSettingsIfNeeded()
        }
    }
    var liveWeatherSettings = LiveWeatherSettings() {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettingsIfNeeded()
        }
    }
    var latestLiveWeather: LiveWeatherSnapshot? {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettingsIfNeeded()
        }
    }
    var liveWeatherStatus: LiveWeatherStatus = .idle

    var isLiveWeatherActive: Bool {
        weatherSourceMode == .liveWeather
    }

    var liveWeatherControlsWind: Bool {
        isLiveWeatherActive && sensorToggles.hasAnemometer
    }

    var liveWeatherControlsSeaTemperature: Bool {
        isLiveWeatherActive && sensorToggles.hasWaterTempSensor
    }

    var liveWeatherControlsAirTemperature: Bool {
        isLiveWeatherActive && sensorToggles.hasAirTempSensor
    }

    var liveWeatherControlsHumidity: Bool {
        isLiveWeatherActive && sensorToggles.hasHumidtySensor
    }

    var liveWeatherControlsBarometer: Bool {
        isLiveWeatherActive && sensorToggles.hasBarometer
    }

    // MARK: - Dashboard Indicator

    var isTransmitting: Bool = false
    var endpointStatuses: [UUID: OutputEndpointStatus] = [:]
    var latestTransportStatus: OutputEndpointStatus?
    var transportHistory: [TransportHistoryEvent] = []

    // MARK: - Console

    /// Unified record backing both `outputMessages` (kept for existing API/tests) and the
    /// console UI. `Identifiable` so views can snapshot this array once per render and use a
    /// stable per-record id instead of re-deriving text/timestamp from separately-read,
    /// live-mutating collections (see `ConsoleView`).
    struct OutputMessageRecord: Identifiable {
        let id = UUID()
        let sentence: String
        let timestamp: Date
    }

    var outputMessages: [String] = []
    /// Read-only outside this type; `ConsoleView` snapshots this once per render (e.g. via
    /// `Array(nmeaManager.outputMessageRecords.enumerated())`) rather than separately reading
    /// `.indices`/`outputMessages[index]`/`outputMessageTimestamp(at:)`, which is unsafe because
    /// `LazyVStack` defers row materialization and the array can be pruned (every ~50ms while
    /// transmitting) between when `.indices` is captured and when a row is actually laid out.
    var outputMessageRecords: [OutputMessageRecord] = []
    var totalSentCount: Int = 0
    /// Bumped when throttled console rows are flushed to `outputMessageRecords` (see `ConsoleView`).
    var consoleDisplayGeneration: UInt64 = 0

    // MARK: - Engine State

    var latestSnapshot: SimulationSnapshot?

    var lastSimulationTickDate: Date?
    @ObservationIgnored
    var lastEmissionDates: [NMEASentenceType: Date] = [:]
    var sentenceIntervals: [NMEASentenceType: TimeInterval] = [:] {
        didSet { persistSettingsIfNeeded() }
    }
    var sendRelativeWind = true
    var previousTurnReferenceHeading: Double?
    var totalLogDistanceNm: Double = 0
    var totalTripDistanceNm: Double = 0
    private var isRestoringSettings = false
    var isApplyingSimulationTick = false
    var isApplyingHardwareProfile = false
    var isSynchronizingEndpoints = false

    @ObservationIgnored
    var pendingTransmissions: [PendingTransmission] = []
    @ObservationIgnored var liveWeatherTask: Task<Bool, Never>?
    /// Authoritative engine fields while the fast transmit timer runs off the main thread.
    @ObservationIgnored var transmitRuntime: SimulationState?
    @ObservationIgnored var consoleRecordBuffer: [OutputMessageRecord] = []
    @ObservationIgnored var consoleFlushWorkItem: DispatchWorkItem?
    /// Guards `consoleRecordBuffer`, `consoleFlushWorkItem`, and `transmittedTrueHeading`.
    /// The simulation queue appends; the main thread flushes and reads.
    @ObservationIgnored let consoleLock = NSLock()
    /// True heading of the newest HDT in the console buffer. The map reads this while
    /// transmitting so it matches a sentence the buffer already contains.
    @ObservationIgnored var transmittedTrueHeading: Double?
    /// Latest runtime waiting to be mirrored onto `@Observable` fields on the main thread.
    /// Coalesced so a busy main queue never accumulates one apply per 50 ms tick.
    @ObservationIgnored var pendingRuntimeApply: SimulationState?
    @ObservationIgnored var displayPublishWorkItem: DispatchWorkItem?
    @ObservationIgnored var lastApplyDuration: TimeInterval = 0
    @ObservationIgnored let runtimeApplyLock = NSLock()

    /// Mean-reverting offsets around the last live-weather snapshot (OU-style; small, smooth gusts).
    var liveWeatherWindSpeedOffsetKt: Double = 0
    var liveWeatherWindDirectionOffsetDeg: Double = 0
    var liveWeatherNoiseBaselineFetchDate: Date?

    struct TackAnimationState {
        let startDate: Date
        let duration: TimeInterval
        let fromTrueHeading: Double
        let toTrueHeading: Double

        func trueHeading(at date: Date) -> Double {
            let rawT = date.timeIntervalSince(startDate) / duration
            let t = min(1, max(0, rawT))
            let smooth = t * t * (3 - 2 * t)
            let delta = calculateShortestRotation(from: fromTrueHeading, to: toTrueHeading)
            return normalizeAngle(fromTrueHeading + delta * smooth)
        }

        func isComplete(at date: Date) -> Bool {
            date.timeIntervalSince(startDate) >= duration - 1e-4
        }
    }

    var tackAnimationState: TackAnimationState?
    @ObservationIgnored var tackAnimationTimer: Timer?

    /// Exposed for `SimulationInputMirror` (the struct lives outside this file).
    var tackAnimationInProgress: Bool { tackAnimationState != nil }

    init(
        userDefaults: UserDefaults = .standard,
        weatherService: any WeatherService = GlobalFallbackWeatherService(),
        vesselStore: (any VesselProfileStoring)? = nil
    ) {
        isRestoringSettings = true
        self.persistenceManager = PersistenceManager(userDefaults: userDefaults)
        self.weatherService = weatherService
        let store = vesselStore ?? Self.makeVesselStore(userDefaults: userDefaults)
        let repository = VesselProfileRepository(store: store)
        self.vesselRepository = repository
        self.vesselStoreError = repository.loadError
        self.vessels = repository.profiles
        simulationQueue.setSpecific(key: Self.simulationQueueMarker, value: 1)
        sentenceIntervals = Self.defaultSentenceIntervals
        perSentenceTalkerID = Self.defaultTalkerIDs
        transportManager.delegate = self
        if let settings = persistenceManager.loadSettings() {
            apply(settings: settings)
        } else if repository.loadError != nil {
            activeVesselState = .unresolved(storedReference: FileVesselProfileStore.fileName)
            isApplyingVesselSelection = true
            boatProfile = .nimana
            isApplyingVesselSelection = false
        }
        normalizeOutputEndpoints()
        adoptHoistedSails()
        isRestoringSettings = false
        syncInputMirror()
        if weatherSourceMode == .liveWeather {
            refreshLiveWeather(force: true)
        }
    }

    deinit {
        tackAnimationTimer?.invalidate()
    }

    func persistLiveSettings() {
        persistSettingsIfNeeded()
    }

    func clearOutputMessages() {
        outputMessages.removeAll()
        outputMessageRecords.removeAll()
        consoleLock.lock()
        consoleRecordBuffer.removeAll()
        consoleLock.unlock()
        consoleDisplayGeneration &+= 1
    }

    /// Clipboard export text for side-by-side comparison with Extasy's NMEA terminal.
    /// Format: `HH:mm:ss.SSS  $sentence` (one line per record).
    func nmeaConsoleExportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return allOutputMessageRecords.map { record in
            let sentence = record.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(formatter.string(from: record.timestamp))  \(sentence)"
        }.joined(separator: "\n")
    }

    /// Clipboard export text for transport history events.
    func transportHistoryExportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return transportHistory.map { event in
            "\(formatter.string(from: event.timestamp))  [\(event.category.rawValue)/\(event.level.rawValue)] \(event.message)"
        }.joined(separator: "\n")
    }

    func outputMessageTimestamp(at index: Int) -> Date? {
        let records = allOutputMessageRecords
        guard index >= 0, index < records.count else {
            return nil
        }
        return records[index].timestamp
    }

    /// Visible console rows plus any not yet flushed from the fast transmit queue.
    var allOutputMessageRecords: [OutputMessageRecord] {
        consoleLock.lock()
        let buffered = consoleRecordBuffer
        consoleLock.unlock()
        return outputMessageRecords + buffered
    }

    func applyPreset(_ preset: SimulationPreset) {
        guard weatherSourceMode == .manual else {
            return
        }

        switch preset {
        case .harborCalm:
            twd = configuredValue(type: .windDirection, center: 75, offset: 6)
            tws = configuredValue(type: .windSpeed, center: 5, offset: 1.5)
            speed = configuredValue(type: .speedLog, center: 4.5, offset: 0.6)
            depth = configuredValue(type: .depth, center: 12, offset: 0.8)
            seaTemp = configuredValue(type: .seaTemp, center: 22, offset: 0.4)
            airTemp = configuredValue(type: .airTemp, center: 24, offset: 1.2)
            humidity = configuredValue(type: .humidity, center: 58, offset: 6)
            barometer = configuredValue(type: .barometer, center: 1017, offset: 2)
            heading = configuredValue(type: .magneticCompass, center: 85, offset: 4)
            gyroHeading = configuredValue(type: .gyroCompass, center: 85, offset: 2)
            gpsData.speedOverGround = 4.5
            gpsData.courseOverGround = 85
            faultInjection = FaultInjectionSettings()
        case .lightWeather:
            twd = configuredValue(type: .windDirection, center: 120, offset: 14)
            tws = configuredValue(type: .windSpeed, center: 13, offset: 3)
            speed = configuredValue(type: .speedLog, center: 6.8, offset: 1.2)
            depth = configuredValue(type: .depth, center: 18, offset: 1.2)
            seaTemp = configuredValue(type: .seaTemp, center: 19, offset: 0.8)
            airTemp = configuredValue(type: .airTemp, center: 21, offset: 2)
            humidity = configuredValue(type: .humidity, center: 68, offset: 8)
            barometer = configuredValue(type: .barometer, center: 1013, offset: 4)
            heading = configuredValue(type: .magneticCompass, center: 110, offset: 8)
            gyroHeading = configuredValue(type: .gyroCompass, center: 112, offset: 4)
            gpsData.speedOverGround = 7.1
            gpsData.courseOverGround = 111
            faultInjection = FaultInjectionSettings()
        case .stormyWeather:
            twd = configuredValue(type: .windDirection, center: 210, offset: 28)
            tws = configuredValue(type: .windSpeed, center: 32, offset: 8)
            speed = configuredValue(type: .speedLog, center: 10.5, offset: 2.6)
            depth = configuredValue(type: .depth, center: 35, offset: 3)
            seaTemp = configuredValue(type: .seaTemp, center: 14, offset: 1.5)
            airTemp = configuredValue(type: .airTemp, center: 11, offset: 3)
            humidity = configuredValue(type: .humidity, center: 84, offset: 10)
            barometer = configuredValue(type: .barometer, center: 995, offset: 8)
            heading = configuredValue(type: .magneticCompass, center: 200, offset: 20)
            gyroHeading = configuredValue(type: .gyroCompass, center: 205, offset: 12)
            gpsData.speedOverGround = 12
            gpsData.courseOverGround = 202
            faultInjection = FaultInjectionSettings(
                isEnabled: false,
                dropRate: 0,
                delayRate: 0,
                checksumCorruptionRate: 0,
                invalidDataRate: 0,
                maximumDelayCycles: 2
            )
        }

        selectedPreset = preset
        persistSettingsIfNeeded()
    }

    func sendAllSelectedNMEA() {
        guard vesselAllowsSimulation else {
            appendHistoryEvent(level: .warning, category: .lifecycle, message: "Select a vessel before transmitting.")
            return
        }
        if transmitRuntime != nil {
            simulationQueue.async { [weak self] in
                self?.runSimulationCycle()
            }
        } else {
            runSimulationCycle()
        }
    }

    func startSimulation() {
        guard vesselAllowsSimulation else {
            appendHistoryEvent(level: .warning, category: .lifecycle, message: "Select a vessel before transmitting.")
            return
        }
        syncPrimaryOutputEndpoint()
        stopSimulation()
        resetEngineForNewRun()

        if weatherSourceMode == .liveWeather, latestLiveWeather == nil {
            startSimulationWithFreshLiveWeather()
            return
        }

        beginSimulationRun()
    }

    func beginSimulationRun() {
        guard isTimerSelected else {
            appendHistoryEvent(level: .connected, category: .lifecycle, message: "Single transmission sent")
            runSimulationCycle()
            return
        }

        refreshEndpointConnectionSignatures()
        stopSimulationTimer()

        isTransmitting = true
        appendHistoryEvent(level: .connected, category: .lifecycle, message: "Simulation started")

        // Capture initial runtime state and input mirror on the main thread
        // to avoid reading @Observable properties from the simulation queue (data race).
        syncInputMirror()
        let initialRuntime = SimulationState(from: self)
        simulationQueue.async { [weak self] in
            guard let self else { return }
            self.transmitRuntime = initialRuntime
            self.startSimulationTimer()
            self.runSimulationCycle()
        }
    }

    func stopSimulation() {
        let wasRunning = isTransmitting || simulationTimer != nil
        isTransmitting = false
        tackAnimationTimer?.invalidate()
        tackAnimationTimer = nil
        tackAnimationState = nil
        activeManeuver = nil
        consoleLock.lock()
        transmittedTrueHeading = nil
        consoleLock.unlock()
        cancelDisplayPublish()
        stopSimulationTimer()
        persistenceManager.cancelPendingPersist()
        consoleLock.lock()
        consoleFlushWorkItem?.cancel()
        consoleFlushWorkItem = nil
        consoleLock.unlock()

        if wasRunning {
            var runtimeToApply: SimulationState?
            simulationQueue.sync { [weak self] in
                guard let self else { return }
                runtimeToApply = self.transmitRuntime
                self.transmitRuntime = nil
            }
            if let runtimeToApply {
                applyRuntimeToMain(runtimeToApply, flushConsoleImmediately: true)
            }
        } else {
            transmitRuntime = nil
        }

        if !wasRunning {
            liveWeatherTask?.cancel()
            liveWeatherTask = nil
        }
        resetTransportConnections()
        transportManager.clearSignatures()
        var latestIdleStatus: OutputEndpointStatus?

        for endpoint in outputEndpoints {
            let idleStatus = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .idle,
                message: "\(endpoint.transport.rawValue.uppercased()) \(endpoint.effectiveHost):\(endpoint.port) idle"
            )
            endpointStatuses[endpoint.id] = idleStatus
            if latestIdleStatus == nil {
                latestIdleStatus = idleStatus
            }
        }
        latestTransportStatus = latestIdleStatus

        if wasRunning {
            if weatherSourceMode == .liveWeather {
                applyResolvedLiveWeatherValues()
            }
            appendHistoryEvent(level: .idle, category: .lifecycle, message: "Simulation stopped")
        }
    }

    func setInterval(_ interval: TimeInterval, for sentence: NMEASentenceType) {
        if sentenceRateMode == .realistic {
            sentenceRateMode = .custom
            selectedProfile = .custom
        }
        sentenceIntervals[sentence] = max(0, interval)
    }

    func sentenceInterval(for sentence: NMEASentenceType) -> Double {
        effectiveInterval(for: sentence)
    }

    var isSentenceIntervalEditable: Bool {
        sentenceRateMode == .custom
    }

    func talkerID(for sentence: NMEASentenceType) -> String {
        perSentenceTalkerID[sentence] ?? talkerID
    }

    func effectiveInterval(for sentence: NMEASentenceType) -> TimeInterval {
        if let configured = sentenceIntervals[sentence] {
            return configured
        }
        return interval
    }

    func applyDefaultSentenceIntervals() {
        sentenceIntervals = Self.defaultSentenceIntervals
    }

    func runSimulationCycle(at timestamp: Date = .now) {
        guard vesselAllowsSimulation else { return }
        if transmitRuntime != nil {
            runTransmitSimulationCycle(at: timestamp)
            return
        }

        performIdleSimulationCycle(at: timestamp)
    }

    func appendHistoryEvent(
        endpointID: UUID? = nil,
        level: TransportStatusLevel,
        category: TransportHistoryEvent.Category,
        message: String,
        timestamp: Date = .now
    ) {
        transportHistory.append(
            TransportHistoryEvent(
                endpointID: endpointID,
                level: level,
                category: category,
                message: message,
                timestamp: timestamp
            )
        )

        if transportHistory.count > 200 {
            transportHistory.removeFirst(transportHistory.count - 200)
        }
    }

    func persistSettingsIfNeeded() {
        syncInputMirror()
        persistenceManager.persistIfNeeded(
            isRestoring: isRestoringSettings,
            isApplyingTick: isApplyingSimulationTick
        ) { [self] in
            makeSettingsSnapshot()
        }
    }

    /// Copies every sim-queue-visible property into the lock-protected mirror.
    /// Called from every relevant `didSet` (via `persistSettingsIfNeeded`), from
    /// `applyRuntimeToMain`, and before starting a simulation run.
    func syncInputMirror() {
        let snapshot = SimulationInputMirror(from: self)
        inputMirrorLock.lock()
        inputMirror = snapshot
        inputMirrorLock.unlock()
    }

    /// Returns a copy of the input mirror for use on the simulation queue.
    func readInputMirror() -> SimulationInputMirror? {
        inputMirrorLock.lock()
        let snapshot = inputMirror
        inputMirrorLock.unlock()
        return snapshot
    }

    /// Queue-side tack install. The next tick reads this mirror instead of a stale main-thread gyro.
    func writeTackCommandToMirror(
        trueHeading: Double,
        magneticHeading: Double?,
        hasGyro: Bool,
        hasCompass: Bool
    ) {
        inputMirrorLock.lock()
        defer { inputMirrorLock.unlock() }
        guard var mirror = inputMirror else { return }
        mirror.tackAnimationInProgress = true
        if hasGyro {
            mirror.gyroHeading.value = trueHeading
            mirror.gyroHeading.centerValue = trueHeading.clamped(to: mirror.gyroHeading.range)
        }
        if hasCompass, let magneticHeading {
            mirror.heading.value = magneticHeading
            mirror.heading.centerValue = magneticHeading.clamped(to: mirror.heading.range)
        }
        inputMirror = mirror
    }

    func scheduleDebouncedSimulationPersist() {
        persistenceManager.scheduleDebouncedPersist(
            delay: Self.simulationValuePersistDebounceInterval
        ) { [weak self] in
            self?.makeSettingsSnapshot()
        }
    }

    var persistSettingsInvocationCount: Int {
        persistenceManager.invocationCount
    }

    /// Export current settings to JSON (File menu).
    func makeSettingsSnapshotForExport() -> SimulatorSettings {
        makeSettingsSnapshot()
    }

    /// Import settings from JSON (File menu) — same path as launch restore.
    func applyImportedSettings(_ settings: SimulatorSettings) {
        apply(settings: settings)
    }



    private static func makeVesselStore(userDefaults: UserDefaults) -> any VesselProfileStoring {
        if userDefaults === UserDefaults.standard {
            return FileVesselProfileStore.applicationSupport()
        }
        return InMemoryVesselProfileStore()
    }

    var vesselAllowsSimulation: Bool {
        vesselStoreError == nil && {
            if case .resolved = activeVesselState { return true }
            return false
        }()
    }

    var activeVesselName: String {
        switch activeVesselState {
        case .resolved(let id):
            return vesselRepository.profile(id: id)?.name ?? "Vessel"
        case .unresolved:
            return "No vessel"
        }
    }

    var activeVesselSummary: String {
        if let vesselStoreError {
            return "Vessel profiles could not be read (\(vesselStoreError)). The saved file was left in place."
        }
        switch activeVesselState {
        case .resolved(let id):
            return vesselRepository.profile(id: id)?.summary ?? "Select a vessel."
        case .unresolved(let storedReference):
            if storedReference.isEmpty {
                return "Select a vessel. The saved vessel was not found."
            }
            return "Select a vessel. Saved reference \(storedReference) was not found."
        }
    }

    var selectedVesselID: UUID? {
        if case .resolved(let id) = activeVesselState { return id }
        return nil
    }

    private var persistedVesselReference: String {
        switch activeVesselState {
        case .resolved(let id):
            return id.uuidString
        case .unresolved(let storedReference):
            return storedReference
        }
    }

    func selectVessel(_ id: UUID) {
        guard vesselStoreError == nil, let profile = vesselRepository.profile(id: id) else { return }
        isApplyingVesselSelection = true
        activeVesselState = .resolved(id)
        boatProfile = profile.sailingKey
        isApplyingVesselSelection = false
        adoptHoistedSails()
        persistSettingsIfNeeded()
    }

    @discardableResult
    func createCustomVessel(name: String, modelName: String? = nil, constructionYear: Int? = nil) throws -> VesselProfile {
        let profile = try vesselRepository.createCustomVessel(name: name, modelName: modelName, constructionYear: constructionYear)
        vessels = vesselRepository.profiles
        return profile
    }

    func renameVessel(_ id: UUID, to name: String) throws {
        try vesselRepository.renameVessel(id, to: name)
        vessels = vesselRepository.profiles
    }

    func updateCustomVessel(_ id: UUID, name: String, modelName: String?, constructionYear: Int?) throws {
        try vesselRepository.updateCustomVessel(id, name: name, modelName: modelName, constructionYear: constructionYear)
        vessels = vesselRepository.profiles
    }

    func updateCustomVessel(_ id: UUID, metadata: VesselEditableMetadata) throws {
        try vesselRepository.updateCustomVessel(id, metadata: metadata)
        vessels = vesselRepository.profiles
    }

    func saveProfileEdits(_ id: UUID, metadata: VesselEditableMetadata?, inventory: [SailRecord]) throws {
        try vesselRepository.saveProfileEdits(id, metadata: metadata, inventory: inventory)
        vessels = vesselRepository.profiles
        if selectedVesselID == id {
            reconcileHoistedSailsWithActiveInventory()
        }
    }

    func replaceActiveSails(_ id: UUID, with selection: ActiveSailSelection) throws {
        try vesselRepository.replaceActiveSails(id, with: selection)
        vessels = vesselRepository.profiles
    }

    /// Copies the active vessel's saved sail selection into the runtime hoisted-sail record.
    /// Called when the active vessel changes, at launch, and when the selection becomes unresolved.
    func adoptHoistedSails() {
        if let id = selectedVesselID, let profile = vesselRepository.profile(id: id) {
            sailConfiguration = profile.activeSails.runtimeConfiguration
        } else {
            sailConfiguration = SailConfiguration()
        }
        publishHoistedConfiguration()
    }

    /// Session hoist. Does not write the vessel's saved selection.
    func setHoistedSails(_ selection: ActiveSailSelection) throws {
        guard let id = selectedVesselID, let profile = vesselRepository.profile(id: id) else {
            throw VesselProfileStoreError.invalidProfileData("Select a vessel before changing hoisted sails.")
        }
        var selection = selection
        let previousMain = sailConfiguration.mainSailID
        if selection.mainsailID?.uuidString != previousMain {
            selection.mainsailReef = Self.reefFitting(selection.mainsailReef, mainsail: profile.inventory.first { $0.id == selection.mainsailID })
        }
        if selection.mainsailID == nil {
            selection.mainsailReef = .full
        }
        try VesselProfileRepository.validateActiveSails(selection, inventory: profile.inventory)
        sailConfiguration = selection.runtimeConfiguration
        publishHoistedConfiguration()
    }

    /// Drops hoisted sails that are no longer in the active inventory. Other hoisted slots stay.
    func reconcileHoistedSailsWithActiveInventory() {
        guard let id = selectedVesselID, let profile = vesselRepository.profile(id: id) else {
            sailConfiguration = SailConfiguration()
            publishHoistedConfiguration()
            return
        }
        var selection = ActiveSailSelection(
            mainsailID: sailConfiguration.mainSailID.flatMap(UUID.init(uuidString:)),
            headsailID: sailConfiguration.headsailID.flatMap(UUID.init(uuidString:)),
            downwindSailID: sailConfiguration.downwindSailID.flatMap(UUID.init(uuidString:)),
            mainsailReef: sailConfiguration.mainsailReef
        )
        selection = selection.clearingSails(absentFrom: profile.inventory)
        if let mainID = selection.mainsailID {
            selection.mainsailReef = Self.reefFitting(selection.mainsailReef, mainsail: profile.inventory.first { $0.id == mainID })
        }
        sailConfiguration = selection.runtimeConfiguration
        publishHoistedConfiguration()
    }

    private static func reefFitting(_ reef: ReefStep, mainsail: SailRecord?) -> ReefStep {
        guard let count = mainsail?.mainsail?.reefCount else { return reef }
        let used: Int
        switch reef {
        case .full: used = 0
        case .reef1: used = 1
        case .reef2: used = 2
        case .reef3: used = 3
        }
        return used > count ? .full : reef
    }

    /// Makes the current hoist and vessel the observation snapshot, including a running transmit state.
    func publishHoistedConfiguration() {
        vesselObservation.sailConfiguration = sailConfiguration
        vesselObservation.referenceProfile = boatProfile
        syncInputMirror()
        let sails = sailConfiguration
        let reference = boatProfile
        let publish = {
            self.transmitRuntime?.sailConfiguration = sails
            self.transmitRuntime?.vesselObservation.sailConfiguration = sails
            self.transmitRuntime?.vesselObservation.referenceProfile = reference
        }
        if DispatchQueue.getSpecific(key: Self.simulationQueueMarker) != nil {
            publish()
        } else {
            simulationQueue.sync(execute: publish)
        }
    }

    @discardableResult
    func duplicateVessel(_ id: UUID) throws -> VesselProfile {
        let copy = try vesselRepository.duplicateVessel(id)
        vessels = vesselRepository.profiles
        return copy
    }

    func deleteCustomVessel(_ id: UUID) throws {
        try vesselRepository.deleteCustomVessel(id)
        vessels = vesselRepository.profiles
        if case .resolved(let active) = activeVesselState, active == id {
            isApplyingVesselSelection = true
            activeVesselState = .unresolved(storedReference: id.uuidString)
            boatProfile = .nimana
            isApplyingVesselSelection = false
            if isTransmitting || simulationTimer != nil {
                stopSimulation()
            }
            adoptHoistedSails()
            persistSettingsIfNeeded()
        }
    }

    private func applyStoredVesselSelection(_ settings: SimulatorSettings) {
        if vesselStoreError != nil {
            let reference = settings.vesselSelectionWasStored ? (settings.activeVesselID ?? "") : FileVesselProfileStore.fileName
            activeVesselState = .unresolved(storedReference: reference)
            isApplyingVesselSelection = true
            boatProfile = .nimana
            isApplyingVesselSelection = false
            return
        }
        guard settings.vesselSelectionWasStored else {
            activeVesselState = .resolved(BuiltInVesselID.extasy)
            isApplyingVesselSelection = true
            boatProfile = .beneteauFirst407
            isApplyingVesselSelection = false
            return
        }
        let raw = settings.activeVesselID ?? ""
        if let id = UUID(uuidString: raw), vesselRepository.profile(id: id) != nil {
            activeVesselState = .resolved(id)
            isApplyingVesselSelection = true
            boatProfile = vesselRepository.profile(id: id)?.sailingKey ?? .nimana
            isApplyingVesselSelection = false
        } else {
            activeVesselState = .unresolved(storedReference: raw)
            isApplyingVesselSelection = true
            boatProfile = .nimana
            isApplyingVesselSelection = false
        }
    }

    private func makeSettingsSnapshot() -> SimulatorSettings {
        SimulatorSettings(
            ip: ip,
            port: port,
            talkerID: talkerID,
            outputEndpoints: outputEndpoints,
            sentenceIntervals: Dictionary(uniqueKeysWithValues: sentenceIntervals.map { ($0.key.rawValue, $0.value) }),
            isTimerSelected: isTimerSelected,
            interval: interval,
            sentenceToggles: sentenceToggles,
            sensorToggles: sensorToggles,
            twd: twd,
            tws: tws,
            speed: speed,
            depth: depth,
            depthOffsetMeters: depthOffsetMeters,
            seaTemp: seaTemp,
            airTemp: airTemp,
            humidity: humidity,
            barometer: barometer,
            heading: heading,
            gyroHeading: gyroHeading,
            gpsData: gpsData,
            faultInjection: faultInjection,
            mwvReferenceMode: mwvReferenceMode,
            selectedPreset: selectedPreset,
            selectedProfile: selectedProfile,
            sentenceRateMode: sentenceRateMode,
            perSentenceTalkerID: Dictionary(uniqueKeysWithValues: perSentenceTalkerID.map { ($0.key.rawValue, $0.value) }),
            boatProfile: boatProfile,
            boatSpeedMode: boatSpeedMode,
            weatherSourceMode: weatherSourceMode,
            liveWeatherSettings: liveWeatherSettings,
            latestLiveWeather: latestLiveWeather,
            waypointNavigation: waypointNavigation,
            maneuverSettings: maneuverSettings,
            activeVesselID: persistedVesselReference,
            vesselSelectionWasStored: true
        )
    }

    private func apply(settings: SimulatorSettings) {
        isRestoringSettings = true

        ip = settings.ip
        port = settings.port
        talkerID = settings.talkerID
        outputEndpoints = settings.outputEndpoints
        sentenceIntervals = Dictionary(
            uniqueKeysWithValues: NMEASentenceType.allCases.map { type in
                (type, settings.sentenceIntervals[type.rawValue] ?? Self.defaultSentenceIntervals[type] ?? 1.0)
            }
        )
        selectedProfile = settings.selectedProfile
        sentenceRateMode = settings.sentenceRateMode
        perSentenceTalkerID = Dictionary(
            uniqueKeysWithValues: NMEASentenceType.allCases.map { type in
                (type, settings.perSentenceTalkerID[type.rawValue] ?? Self.defaultTalkerIDs[type] ?? settings.talkerID)
            }
        )
        isTimerSelected = settings.isTimerSelected
        interval = max(0.1, settings.interval)
        sentenceToggles = settings.sentenceToggles
        sensorToggles = settings.sensorToggles
        twd = settings.twd
        tws = settings.tws
        speed = settings.speed
        depth = settings.depth
        depthOffsetMeters = settings.depthOffsetMeters
        seaTemp = settings.seaTemp
        airTemp = settings.airTemp
        humidity = settings.humidity
        barometer = settings.barometer
        heading = settings.heading
        gyroHeading = settings.gyroHeading
        gpsData = settings.gpsData
        faultInjection = settings.faultInjection
        mwvReferenceMode = settings.mwvReferenceMode
        selectedPreset = settings.selectedPreset
        boatSpeedMode = settings.boatSpeedMode
        weatherSourceMode = settings.weatherSourceMode
        liveWeatherSettings = settings.liveWeatherSettings
        latestLiveWeather = settings.latestLiveWeather
        waypointNavigation = settings.waypointNavigation
        maneuverSettings = settings.maneuverSettings
        applyStoredVesselSelection(settings)
        liveWeatherStatus = weatherSourceMode == .liveWeather
            ? LiveWeatherStatus(
                state: latestLiveWeather == nil ? .idle : .ready,
                message: latestLiveWeather == nil ? "Live weather not fetched yet." : "Using cached live weather.",
                lastUpdated: latestLiveWeather?.fetchedAt
            )
            : .idle

        isRestoringSettings = false
    }

    private func configuredValue(
        type: SimulatedValueType,
        center: Double,
        offset: Double
    ) -> SimulatedValue {
        SimulatedValue(type: type, center: center, offset: offset, value: center)
    }

    private func resetEngineForNewRun() {
        lastSimulationTickDate = nil
        lastEmissionDates.removeAll()
        previousTurnReferenceHeading = nil
        sendRelativeWind = true
        totalTripDistanceNm = 0
        pendingTransmissions.removeAll()
    }

    private func restartTimer() {
        stopSimulationTimer()
        // Capture fallback runtime on main to avoid reading @Observable state on the sim queue.
        let fallbackRuntime = SimulationState(from: self)
        syncInputMirror()
        simulationQueue.async { [weak self] in
            guard let self else { return }
            if self.transmitRuntime == nil {
                self.transmitRuntime = fallbackRuntime
            }
            self.startSimulationTimer()
        }
    }

    private func handleTimerSelectionChange() {
        guard !isRestoringSettings else {
            return
        }

        if isTimerSelected {
            if isTransmitting && simulationTimer == nil {
                restartTimer()
                appendHistoryEvent(level: .connected, category: .lifecycle, message: "Timer re-enabled")
            }
            return
        }

        if simulationTimer != nil || isTransmitting {
            stopSimulationTimer()
            cancelDisplayPublish()
            isTransmitting = false
            var runtimeToApply: SimulationState?
            simulationQueue.sync { [weak self] in
                guard let self else { return }
                runtimeToApply = self.transmitRuntime
                self.transmitRuntime = nil
            }
            if let runtimeToApply {
                applyRuntimeToMain(runtimeToApply, flushConsoleImmediately: true)
            }
            appendHistoryEvent(level: .idle, category: .lifecycle, message: "Timer disabled; continuous transmission stopped")
        }
    }

    func resolvedTrueHeading(magneticHeading: Double?, gyroHeading: Double?, variation: Double) -> Double? {
        if let gyroHeading {
            return normalizeAngle(gyroHeading)
        }

        guard let magneticHeading else {
            return nil
        }

        return normalizeAngle(magneticHeading + variation)
    }


    func simulatedMagneticVariation(for gpsData: GPSData, at timestamp: Date) -> Double {
        SimulationEngine.simulatedMagneticVariation(for: gpsData, at: timestamp)
    }

    func simulatedCompassDeviation(heading: Double?) -> Double {
        SimulationEngine.simulatedCompassDeviation(heading: heading)
    }


    func nextMWVReference(in snapshot: SimulationSnapshot) -> String {
        nextMWVReference(
            in: snapshot,
            sendRelativeWind: &sendRelativeWind,
            mwvReferenceMode: mwvReferenceMode
        )
    }

    /// Off-main variant: uses captured toggles to avoid data races from the simulation queue.
    func nextMWVReference(in snapshot: SimulationSnapshot, sendRelativeWind: inout Bool, mwvReferenceMode: MWVReferenceMode) -> String {
        let hasApparent = computeAWA(from: snapshot) != nil && computeAWS(from: snapshot) != nil
        let hasTrue = computeTWA(from: snapshot) != nil && computeTWS(from: snapshot) != nil

        switch mwvReferenceMode {
        case .relative:
            return hasApparent ? "R" : "T"
        case .trueReference:
            return hasTrue ? "T" : "R"
        case .auto:
            if hasApparent && hasTrue {
                defer { sendRelativeWind.toggle() }
                return sendRelativeWind ? "R" : "T"
            }

            if hasApparent {
                return "R"
            }

            return "T"
        }
    }

    func recordOutputMessage(_ sentence: String, timestamp: Date) {
        let record = OutputMessageRecord(sentence: sentence, timestamp: timestamp)
        if transmitRuntime != nil {
            consoleLock.lock()
            consoleRecordBuffer.append(record)
            if let trueHeading = Self.trueHeading(inHDT: sentence) {
                transmittedTrueHeading = trueHeading
            }
            consoleLock.unlock()
            return
        }

        outputMessageRecords.append(record)
        outputMessages.append(sentence)
        totalSentCount += 1
        pruneOutputMessageRecords(referenceTimestamp: timestamp)
    }

    func pruneOutputMessageRecords(referenceTimestamp: Date) {
        let cutoff = referenceTimestamp.addingTimeInterval(-Self.consoleRetentionInterval)
        outputMessageRecords.removeAll { $0.timestamp < cutoff }

        if outputMessageRecords.count > Self.consoleMaxRecords {
            outputMessageRecords.removeFirst(outputMessageRecords.count - Self.consoleMaxRecords)
        }

        outputMessages = outputMessageRecords.map(\.sentence)
    }

    func sentPerSecond(at timestamp: Date = .now) -> Int {
        let windowStart = timestamp.addingTimeInterval(-1)
        let visibleCount = outputMessageRecords.filter { $0.timestamp >= windowStart }.count
        consoleLock.lock()
        let bufferedCount = consoleRecordBuffer.filter { $0.timestamp >= windowStart }.count
        consoleLock.unlock()
        return visibleCount + bufferedCount
    }

    /// Heading field from `$--HDT,heading,T*hh`. Nil for every other sentence.
    static func trueHeading(inHDT sentence: String) -> Double? {
        guard let marker = sentence.range(of: "HDT,") else { return nil }
        let field = sentence[marker.upperBound...].prefix { $0 != "," }
        return Double(field)
    }

}

// MARK: - Interlock Helpers

extension NMEASimulator {

    /// While transmitting, this is the true heading of the newest HDT already in the
    /// console buffer. Otherwise it is the live gyro, magnetic heading, or COG.
    var geographicBearingDegreesForMap: Double {
        consoleLock.lock()
        let transmitted = transmittedTrueHeading
        consoleLock.unlock()
        if isTransmitting, let transmitted {
            return transmitted
        }
        return mapDashboardBearingBeforeFirstSnapshot()
    }

    var hasAnemometer: Bool {
        sensorToggles.hasAnemometer
    }

    var hasBoatSpeed: Bool {
        sensorToggles.hasSpeedLog || sensorToggles.hasGPS
    }

    var hasTrueHeading: Bool {
        sensorToggles.hasGyro || sensorToggles.hasCompass
    }

    var canSendTrueWind: Bool {
        hasAnemometer && hasBoatSpeed
    }

    var canSendFullWindData: Bool {
        canSendTrueWind && hasTrueHeading
    }
}

