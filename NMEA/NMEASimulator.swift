import Foundation
import Observation
import CoreLocation

@Observable
class NMEASimulator {

    /// Same interval as `scheduleTackTimer` (60 Hz). UI can use short linear motion aligned to tack steps.
    static let tackAnimationTickInterval: TimeInterval = 1.0 / 60.0

    /// Internal scheduler cadence while transmitting; decoupled from the user-facing Send Interval.
    private static let simulationFastTickInterval: TimeInterval = 0.05

    /// UI publish cadence. Engine stays at `simulationFastTickInterval`; views paint at this rate.
    private static let displayPublishInterval: TimeInterval = 0.1
    /// Throttle console / stats `@Observable` churn while transmitting (see `recordOutputMessage`).
    private static let consoleDisplayFlushInterval: TimeInterval = 0.1
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
    @ObservationIgnored private let weatherService: any WeatherService

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

    @ObservationIgnored private let transportManager = TransportManager()
    @ObservationIgnored private let simulationQueue = DispatchQueue(label: "com.marinesimulator.simulation", qos: .userInitiated)
    @ObservationIgnored private var simulationTimer: DispatchSourceTimer?

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
                applyDefaultSentenceIntervals()
            }
            persistSettingsIfNeeded()
        }
    }
    var perSentenceTalkerID: [NMEASentenceType: String] = [:] {
        didSet { persistSettingsIfNeeded() }
    }
    var boatProfile: BoatProfile = .beneteauFirst407 {
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
    private(set) var latestLiveWeather: LiveWeatherSnapshot? {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettingsIfNeeded()
        }
    }
    private(set) var liveWeatherStatus: LiveWeatherStatus = .idle

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
    private(set) var endpointStatuses: [UUID: OutputEndpointStatus] = [:]
    private(set) var latestTransportStatus: OutputEndpointStatus?
    private(set) var transportHistory: [TransportHistoryEvent] = []

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
    private(set) var outputMessageRecords: [OutputMessageRecord] = []
    private(set) var totalSentCount: Int = 0
    /// Bumped when throttled console rows are flushed to `outputMessageRecords` (see `ConsoleView`).
    private(set) var consoleDisplayGeneration: UInt64 = 0

    // MARK: - Engine State

    private(set) var latestSnapshot: SimulationSnapshot?

    private var lastSimulationTickDate: Date?
    private var lastEmissionDates: [NMEASentenceType: Date] = [:]
    var sentenceIntervals: [NMEASentenceType: TimeInterval] = [:] {
        didSet { persistSettingsIfNeeded() }
    }
    private var sendRelativeWind = true
    private var previousTurnReferenceHeading: Double?
    private var totalLogDistanceNm: Double = 0
    private var totalTripDistanceNm: Double = 0
    private var isRestoringSettings = false
    private var isApplyingSimulationTick = false
    var isApplyingHardwareProfile = false
    private var isSynchronizingEndpoints = false

    private var pendingTransmissions: [PendingTransmission] = []
    @ObservationIgnored private var liveWeatherTask: Task<Bool, Never>?
    /// Authoritative engine fields while the fast transmit timer runs off the main thread.
    @ObservationIgnored private var transmitRuntime: SimulationState?
    @ObservationIgnored private var consoleRecordBuffer: [OutputMessageRecord] = []
    @ObservationIgnored private var consoleFlushWorkItem: DispatchWorkItem?
    /// Guards `consoleRecordBuffer` and `consoleFlushWorkItem` which are accessed
    /// from both `simulationQueue` (append) and the main thread (flush / read).
    @ObservationIgnored private let consoleLock = NSLock()
    /// Latest runtime waiting to be mirrored onto `@Observable` fields on the main thread.
    /// Coalesced so a busy main queue never accumulates one apply per 50 ms tick.
    @ObservationIgnored private var pendingRuntimeApply: SimulationState?
    @ObservationIgnored private var displayPublishWorkItem: DispatchWorkItem?
    @ObservationIgnored private let runtimeApplyLock = NSLock()

    /// Mean-reverting offsets around the last live-weather snapshot (OU-style; small, smooth gusts).
    private(set) var liveWeatherWindSpeedOffsetKt: Double = 0
    private(set) var liveWeatherWindDirectionOffsetDeg: Double = 0
    private(set) var liveWeatherNoiseBaselineFetchDate: Date?

    private struct TackAnimationState {
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

    private var tackAnimationState: TackAnimationState?
    @ObservationIgnored private var tackAnimationTimer: Timer?

    /// Exposed for `SimulationInputMirror` (the struct lives outside this file).
    var tackAnimationInProgress: Bool { tackAnimationState != nil }

    init(
        userDefaults: UserDefaults = .standard,
        weatherService: any WeatherService = GlobalFallbackWeatherService()
    ) {
        isRestoringSettings = true
        self.persistenceManager = PersistenceManager(userDefaults: userDefaults)
        self.weatherService = weatherService
        sentenceIntervals = Self.defaultSentenceIntervals
        perSentenceTalkerID = Self.defaultTalkerIDs
        transportManager.delegate = self
        if let settings = persistenceManager.loadSettings() {
            apply(settings: settings)
        }
        normalizeOutputEndpoints()
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
        if transmitRuntime != nil {
            simulationQueue.async { [weak self] in
                self?.runSimulationCycle()
            }
        } else {
            runSimulationCycle()
        }
    }

    func startSimulation() {
        syncPrimaryOutputEndpoint()
        stopSimulation()
        resetEngineForNewRun()

        if weatherSourceMode == .liveWeather, latestLiveWeather == nil {
            startSimulationWithFreshLiveWeather()
            return
        }

        beginSimulationRun()
    }

    private func startSimulationWithFreshLiveWeather() {
        let startupDate = Date.now

        liveWeatherTask?.cancel()
        liveWeatherTask = Task { [weak self] in
            guard let self else { return false }
            defer { self.liveWeatherTask = nil }

            let success = await self.refreshLiveWeatherNow(force: true, at: startupDate)
            guard success || self.latestLiveWeather != nil else {
                self.appendHistoryEvent(level: .warning, category: .lifecycle, message: "Simulation start cancelled: live weather unavailable")
                return false
            }

            self.beginSimulationRun()
            return true
        }
    }

    private func beginSimulationRun() {
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

    func addOutputEndpoint() {
        outputEndpoints.append(
            OutputEndpoint(
                name: "Output \(outputEndpoints.count + 1)",
                host: ip,
                port: port,
                transport: .udp,
                isEnabled: true
            )
        )
    }

    func removeOutputEndpoint(id: OutputEndpoint.ID) {
        guard let index = outputEndpoints.firstIndex(where: { $0.id == id }) else {
            return
        }

        if index == 0 {
            return
        }

        outputEndpoints.remove(at: index)
        endpointStatuses.removeValue(forKey: id)
        if latestTransportStatus?.endpointID == id {
            latestTransportStatus = outputEndpoints.compactMap { endpointStatuses[$0.id] }.last
        }
    }

    func transportStatus(for endpointID: UUID) -> OutputEndpointStatus? {
        endpointStatuses[endpointID]
    }

    func clearTransportHistory() {
        transportHistory.removeAll()
    }

    func refreshLiveWeather(force: Bool = false) {
        if force, let liveWeatherTask {
            liveWeatherTask.cancel()
            self.liveWeatherTask = nil
        } else if liveWeatherTask != nil {
            return
        }

        liveWeatherTask = Task { [weak self] in
            guard let self else { return false }
            defer { self.liveWeatherTask = nil }
            return await self.refreshLiveWeatherNow(force: force)
        }
    }

    @discardableResult
    func refreshLiveWeatherNow(force: Bool = false, at timestamp: Date = .now) async -> Bool {
        guard weatherSourceMode == .liveWeather else {
            liveWeatherStatus = .idle
            return false
        }

        guard sensorToggles.hasGPS else {
            liveWeatherStatus = LiveWeatherStatus(state: .failed, message: "Enable GPS to use live weather.", lastUpdated: latestLiveWeather?.fetchedAt)
            return false
        }

        if !force, !shouldRefreshLiveWeather(at: timestamp) {
            return false
        }

        liveWeatherStatus = LiveWeatherStatus(state: .fetching, message: "Fetching live weather…", lastUpdated: latestLiveWeather?.fetchedAt)

        do {
            let snapshot = try await weatherService.fetchWeather(
                latitude: gpsData.latitude,
                longitude: gpsData.longitude,
                date: timestamp
            )
            guard !Task.isCancelled, weatherSourceMode == .liveWeather else {
                liveWeatherStatus = .idle
                return false
            }
            latestLiveWeather = snapshot
            applyResolvedLiveWeatherValues()
            liveWeatherStatus = LiveWeatherStatus(
                state: .ready,
                message: "Live weather updated from \(snapshot.sourceName).",
                lastUpdated: snapshot.fetchedAt
            )
            return true
        } catch {
            guard !Task.isCancelled, weatherSourceMode == .liveWeather else {
                liveWeatherStatus = .idle
                return false
            }
            liveWeatherStatus = LiveWeatherStatus(
                state: .failed,
                message: latestLiveWeather == nil
                    ? error.localizedDescription
                    : "Live weather refresh failed. Using last good weather. \(error.localizedDescription)",
                lastUpdated: latestLiveWeather?.fetchedAt
            )
            return false
        }
    }

    private func runSimulationCycle(at timestamp: Date = .now) {
        if transmitRuntime != nil {
            runTransmitSimulationCycle(at: timestamp)
            return
        }

        resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting()
        flushPendingTransmissions(at: timestamp)

        let snapshot: SimulationSnapshot
        if shouldAdvanceSimulation(at: timestamp) {
            snapshot = tickSimulation(at: timestamp)
        } else if let latestSnapshot {
            snapshot = latestSnapshot
        } else {
            snapshot = tickSimulation(at: timestamp)
        }

        let dueSentences = scheduledSentenceTypes(at: timestamp, snapshot: snapshot)
        guard !dueSentences.isEmpty else { return }

        let schedule = SentenceScheduler.scheduleSentences(
            dueSentences: dueSentences,
            snapshot: snapshot,
            config: captureSimulationConfig(),
            interval: interval,
            at: timestamp,
            sentenceBuilder: { buildNMEASentences(talkerID: $0, type: $1, snapshot: $2) },
            talkerIDResolver: { talkerID(for: $0) }
        )

        dispatchScheduleResult(schedule, at: timestamp)

        if let flushTime = SentenceScheduler.staggerFlushTimestamp(
            sentenceCount: dueSentences.count, interval: interval, cycleTimestamp: timestamp
        ) {
            flushPendingTransmissions(at: flushTime)
        }
    }

    private func tickSimulation(at timestamp: Date) -> SimulationSnapshot {
        isApplyingSimulationTick = true
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingSimulationTick = false
            }
            scheduleDebouncedSimulationPersist()
        }

        triggerLiveWeatherRefreshIfNeeded(at: timestamp)

        // Build a temporary SimulationState from self, run the engine, then apply results back.
        var state = SimulationState(from: self)
        state.lastSimulationTickDate = lastSimulationTickDate
        state.previousTurnReferenceHeading = previousTurnReferenceHeading
        state.totalLogDistanceNm = totalLogDistanceNm
        state.totalTripDistanceNm = totalTripDistanceNm
        state.sendRelativeWind = sendRelativeWind

        let config = captureSimulationConfig()
        let snapshot = SimulationEngine.tickSimulation(
            state: &state,
            config: config,
            at: timestamp,
            liveWeatherValueGenerator: generateLiveWeatherValue(base:jitter:range:wraps:)
        )

        // Apply engine results back to self.
        twd = state.twd
        tws = state.tws
        speed = state.speed
        depth = state.depth
        seaTemp = state.seaTemp
        airTemp = state.airTemp
        humidity = state.humidity
        barometer = state.barometer
        heading = state.heading
        gyroHeading = state.gyroHeading
        gpsData = state.gpsData
        latestSnapshot = state.latestSnapshot
        lastSimulationTickDate = state.lastSimulationTickDate
        previousTurnReferenceHeading = state.previousTurnReferenceHeading
        totalLogDistanceNm = state.totalLogDistanceNm
        totalTripDistanceNm = state.totalTripDistanceNm
        liveWeatherWindSpeedOffsetKt = state.liveWeatherWindSpeedOffsetKt
        liveWeatherWindDirectionOffsetDeg = state.liveWeatherWindDirectionOffsetDeg
        liveWeatherNoiseBaselineFetchDate = state.liveWeatherNoiseBaselineFetchDate

        return snapshot
    }

    /// Dispatches the result of `SentenceScheduler.scheduleSentences` by performing
    /// the side effects: sending immediate sentences, queueing delayed ones, and logging fault events.
    private func dispatchScheduleResult(_ result: SentenceScheduler.ScheduleResult, at timestamp: Date) {
        for (sentence, _) in result.immediateSentences {
            for endpoint in enabledOutputEndpoints() {
                send(sentence, to: endpoint)
            }
            recordOutputMessage(sentence, timestamp: timestamp)
        }

        for delayed in result.delayedSentences {
            pendingTransmissions.append(PendingTransmission(sentence: delayed.sentence, dueDate: delayed.dueDate))
        }

        for event in result.faultEvents {
            appendHistoryEvent(level: event.level, category: .fault, message: event.message)
        }
    }

    /// Off-main variant: dispatches schedule result using `runtime` for pending transmissions
    /// and dispatches history events to the main thread.
    private func dispatchScheduleResult(
        _ result: SentenceScheduler.ScheduleResult,
        runtime: inout SimulationState,
        endpoints: [OutputEndpoint],
        at timestamp: Date
    ) {
        for (sentence, _) in result.immediateSentences {
            for endpoint in endpoints {
                send(sentence, to: endpoint)
            }
            recordOutputMessage(sentence, timestamp: timestamp)
        }

        for delayed in result.delayedSentences {
            runtime.pendingTransmissions.append(PendingTransmission(sentence: delayed.sentence, dueDate: delayed.dueDate))
        }

        for event in result.faultEvents {
            appendHistoryEventOnMain(level: event.level, category: .fault, message: event.message)
        }
    }

    private func scheduledSentenceTypes(at timestamp: Date, snapshot: SimulationSnapshot) -> [NMEASentenceType] {
        let config = captureSimulationConfig()
        // Use a lightweight inout wrapper so the engine can update lastEmissionDates.
        var emissionState = SimulationState(from: self)
        emissionState.lastEmissionDates = lastEmissionDates
        let result = SimulationEngine.scheduledSentenceTypes(
            state: &emissionState,
            at: timestamp,
            snapshot: snapshot,
            config: config
        )
        lastEmissionDates = emissionState.lastEmissionDates
        return result
    }

    private func enabledOutputEndpoints() -> [OutputEndpoint] {
        if Thread.isMainThread {
            syncPrimaryOutputEndpoint()
            resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting()
        }
        return outputEndpoints.filter(\.isEnabled)
    }

    private func send(_ sentence: String, to endpoint: OutputEndpoint) {
        transportManager.send(sentence, to: endpoint)
    }



    private func recordTransportStatus(_ status: OutputEndpointStatus) {
        let previousStatus = endpointStatuses[status.endpointID]
        let statusChanged = previousStatus?.level != status.level || previousStatus?.message != status.message
        guard statusChanged else {
            return
        }

        endpointStatuses[status.endpointID] = status

        // Update the top-bar indicator:
        //   • Always update for the same endpoint so errors can recover to connected.
        //   • For a different endpoint, surface errors/warnings over idle/connected.
        if latestTransportStatus == nil
            || status.endpointID == latestTransportStatus?.endpointID
            || status.level == .error
            || status.level == .warning {
            latestTransportStatus = status
        }

        appendHistoryEvent(
            endpointID: status.endpointID,
            level: status.level,
            category: .transport,
            message: status.message,
            timestamp: status.updatedAt
        )
    }


    private func appendHistoryEvent(
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

    private func syncPrimaryOutputEndpoint() {
        guard !isSynchronizingEndpoints else {
            return
        }

        isSynchronizingEndpoints = true
        defer { isSynchronizingEndpoints = false }

        if outputEndpoints.isEmpty {
            outputEndpoints = [OutputEndpoint(host: ip, port: port)]
            return
        }

        outputEndpoints[0].host = ip
        outputEndpoints[0].isBroadcast = isBroadcast
        outputEndpoints[0].port = port
    }

    private func normalizeOutputEndpoints() {
        guard !isSynchronizingEndpoints else {
            return
        }

        isSynchronizingEndpoints = true
        defer { isSynchronizingEndpoints = false }

        if outputEndpoints.isEmpty {
            outputEndpoints = [OutputEndpoint(host: ip, port: port)]
        }

        outputEndpoints[0].name = outputEndpoints[0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Primary Output"
            : outputEndpoints[0].name
        outputEndpoints[0].host = outputEndpoints[0].host
        outputEndpoints[0].port = outputEndpoints[0].port

        // Broadcast is UDP-only. Auto-clear an invalid persisted state so the
        // toggle is never left ON-and-disabled with no way for the user to fix it.
        if outputEndpoints[0].transport == .tcp && outputEndpoints[0].isBroadcast {
            outputEndpoints[0].isBroadcast = false
        }

        if ip != outputEndpoints[0].host {
            ip = outputEndpoints[0].host
        }
        if isBroadcast != outputEndpoints[0].isBroadcast {
            isBroadcast = outputEndpoints[0].isBroadcast
        }
        if port != outputEndpoints[0].port {
            port = outputEndpoints[0].port
        }
    }

    private func persistSettingsIfNeeded() {
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
    private func syncInputMirror() {
        let snapshot = SimulationInputMirror(from: self)
        inputMirrorLock.lock()
        inputMirror = snapshot
        inputMirrorLock.unlock()
    }

    /// Returns a copy of the input mirror for use on the simulation queue.
    private func readInputMirror() -> SimulationInputMirror? {
        inputMirrorLock.lock()
        let snapshot = inputMirror
        inputMirrorLock.unlock()
        return snapshot
    }

    private func scheduleDebouncedSimulationPersist() {
        persistenceManager.scheduleDebouncedPersist(
            delay: Self.simulationValuePersistDebounceInterval
        ) { [weak self] in
            self?.makeSettingsSnapshot()
        }
    }

    private func shouldAdvanceSimulation(at timestamp: Date) -> Bool {
        var state = SimulationState(from: self)
        state.lastSimulationTickDate = lastSimulationTickDate
        return SimulationEngine.shouldAdvanceSimulation(state: state, at: timestamp, interval: interval)
    }

    private func resetTransportConnections() {
        transportManager.resetConnections()
    }

    private func resetTransportConnectionsIfTransmitting() {
        transportManager.resetConnectionsIfTransmitting(isTransmitting: isTransmitting)
    }

    private func resetTransportConnectionsIfEndpointTargetsChanged(from oldEndpoints: [OutputEndpoint], to newEndpoints: [OutputEndpoint]) {
        transportManager.resetConnectionsIfEndpointTargetsChanged(from: oldEndpoints, to: newEndpoints, isTransmitting: isTransmitting)
    }

    private func resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting() {
        transportManager.syncEndpointSignatures(from: outputEndpoints, isTransmitting: isTransmitting)
    }

    private func refreshEndpointConnectionSignatures(from endpoints: [OutputEndpoint]? = nil) {
        transportManager.refreshEndpointConnectionSignatures(from: endpoints ?? outputEndpoints)
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
            waypointNavigation: waypointNavigation
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
        boatProfile = settings.boatProfile
        boatSpeedMode = settings.boatSpeedMode
        weatherSourceMode = settings.weatherSourceMode
        liveWeatherSettings = settings.liveWeatherSettings
        latestLiveWeather = settings.latestLiveWeather
        waypointNavigation = settings.waypointNavigation
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

    private var activeLiveWeather: LiveWeatherSnapshot? {
        guard weatherSourceMode == .liveWeather else {
            return nil
        }
        return latestLiveWeather
    }

    private func triggerLiveWeatherRefreshIfNeeded(at timestamp: Date) {
        guard weatherSourceMode == .liveWeather else {
            return
        }

        guard liveWeatherTask == nil, shouldRefreshLiveWeather(at: timestamp) else {
            return
        }

        refreshLiveWeather(force: false)
    }

    private func shouldRefreshLiveWeather(at timestamp: Date) -> Bool {
        guard weatherSourceMode == .liveWeather else {
            return false
        }

        guard let latestLiveWeather else {
            return true
        }

        if timestamp.timeIntervalSince(latestLiveWeather.fetchedAt) >= liveWeatherSettings.refreshInterval {
            return true
        }

        let latestLocation = CLLocation(latitude: latestLiveWeather.latitude, longitude: latestLiveWeather.longitude)
        let currentLocation = CLLocation(latitude: gpsData.latitude, longitude: gpsData.longitude)
        let distanceNM = currentLocation.distance(from: latestLocation) / 1852
        return distanceNM >= liveWeatherSettings.minimumRefreshDistanceNM
    }

    private func resetLiveWeatherWindNoiseState() {
        liveWeatherWindSpeedOffsetKt = 0
        liveWeatherWindDirectionOffsetDeg = 0
        liveWeatherNoiseBaselineFetchDate = nil
    }

    private func syncLiveWeatherWindNoiseBaselineIfNeeded(fetchedAt: Date) {
        if liveWeatherNoiseBaselineFetchDate != fetchedAt {
            liveWeatherNoiseBaselineFetchDate = fetchedAt
            liveWeatherWindSpeedOffsetKt = 0
            liveWeatherWindDirectionOffsetDeg = 0
        }
    }

    /// Smooth, mean-reverting variation around the forecast (not i.i.d. each tick).
    private func evolveLiveWeatherWindNoise(deltaTime: TimeInterval) {
        let dt = min(max(deltaTime, 0), 4)
        guard dt > 0 else { return }

        let zSpeed = unitGaussianRandom()
        let zDir = unitGaussianRandom()

        let thetaSpeed = 0.07
        let sigmaSpeedKt = 0.017
        liveWeatherWindSpeedOffsetKt += -thetaSpeed * liveWeatherWindSpeedOffsetKt * dt + sigmaSpeedKt * sqrt(dt) * zSpeed
        liveWeatherWindSpeedOffsetKt = liveWeatherWindSpeedOffsetKt.clamped(to: -1.1...1.1)

        let thetaDir = 0.06
        let sigmaDirDeg = 0.22
        liveWeatherWindDirectionOffsetDeg += -thetaDir * liveWeatherWindDirectionOffsetDeg * dt + sigmaDirDeg * sqrt(dt) * zDir
        liveWeatherWindDirectionOffsetDeg = liveWeatherWindDirectionOffsetDeg.clamped(to: -10...10)
    }

    private func generateLiveWeatherValue(
        base: Double?,
        jitter: Double,
        range: ClosedRange<Double>,
        wraps: Bool
    ) -> Double? {
        guard let base else {
            return nil
        }

        let offset = Double.random(in: -jitter...jitter)
        if wraps {
            return normalizeAngle(base + offset)
        }

        return (base + offset).clamped(to: range)
    }

    private func applyResolvedLiveWeatherValues() {
        guard let liveWeather = activeLiveWeather else {
            return
        }

        twd.value = sensorToggles.hasAnemometer
            ? liveWeather.trueWindDirection
            : nil
        tws.value = sensorToggles.hasAnemometer
            ? liveWeather.trueWindSpeedKnots
            : nil
        seaTemp.value = sensorToggles.hasWaterTempSensor
            ? liveWeather.seaSurfaceTemperatureCelsius
            : nil
        airTemp.value = sensorToggles.hasAirTempSensor
            ? liveWeather.airTemperatureCelsius
            : nil
        humidity.value = sensorToggles.hasHumidtySensor
            ? liveWeather.relativeHumidityPercent
            : nil
        barometer.value = sensorToggles.hasBarometer
            ? liveWeather.airPressureHectopascals
            : nil
    }

    private func resolvedTrueHeading(magneticHeading: Double?, gyroHeading: Double?, variation: Double) -> Double? {
        if let gyroHeading {
            return normalizeAngle(gyroHeading)
        }

        guard let magneticHeading else {
            return nil
        }

        return normalizeAngle(magneticHeading + variation)
    }


    private func simulatedMagneticVariation(for gpsData: GPSData, at timestamp: Date) -> Double {
        SimulationEngine.simulatedMagneticVariation(for: gpsData, at: timestamp)
    }

    private func simulatedCompassDeviation(heading: Double?) -> Double {
        SimulationEngine.simulatedCompassDeviation(heading: heading)
    }


    func nextMWVReference(in snapshot: SimulationSnapshot) -> String {
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

    private func flushPendingTransmissions(at timestamp: Date) {
        let due = pendingTransmissions.filter { $0.dueDate <= timestamp }
        pendingTransmissions.removeAll { $0.dueDate <= timestamp }

        for pending in due {
            for endpoint in enabledOutputEndpoints() {
                send(pending.sentence, to: endpoint)
            }
            recordOutputMessage(pending.sentence, timestamp: timestamp)
        }
    }

    private func recordOutputMessage(_ sentence: String, timestamp: Date) {
        let record = OutputMessageRecord(sentence: sentence, timestamp: timestamp)
        if transmitRuntime != nil {
            consoleLock.lock()
            consoleRecordBuffer.append(record)
            consoleLock.unlock()
            return
        }

        outputMessageRecords.append(record)
        outputMessages.append(sentence)
        totalSentCount += 1
        pruneOutputMessageRecords(referenceTimestamp: timestamp)
    }

    private func pruneOutputMessageRecords(referenceTimestamp: Date) {
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

    private func scheduleTackTimer() {
        tackAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: Self.tackAnimationTickInterval, repeats: true) { [weak self] _ in
            self?.advanceTackAnimation(at: Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        tackAnimationTimer = timer
    }

    private func advanceTackAnimation(at date: Date) {
        guard let state = tackAnimationState else {
            tackAnimationTimer?.invalidate()
            tackAnimationTimer = nil
            return
        }

        if state.isComplete(at: date) {
            applySimulatedTrueHeading(state.toTrueHeading, at: date)
            tackAnimationState = nil
            tackAnimationTimer?.invalidate()
            tackAnimationTimer = nil
            persistSettingsIfNeeded()
            return
        }

        applySimulatedTrueHeading(state.trueHeading(at: date), at: date)
    }

    private func applySimulatedTrueHeading(_ trueDeg: Double, at date: Date) {
        let variation = simulatedMagneticVariation(for: gpsData, at: date)
        let trueNorm = normalizeAngle(trueDeg)
        if sensorToggles.hasGyro {
            gyroHeading.value = trueNorm
            gyroHeading.centerValue = trueNorm.clamped(to: gyroHeading.range)
        }
        if sensorToggles.hasCompass {
            let mag = normalizeAngle(trueNorm - variation)
            heading.value = mag
            heading.centerValue = mag.clamped(to: heading.range)
        }

        if isTransmitting, let previous = latestSnapshot {
            latestSnapshot = SimulationSnapshot(
                timestamp: date,
                windDirectionTrue: previous.windDirectionTrue,
                windSpeedTrue: previous.windSpeedTrue,
                magneticHeading: sensorToggles.hasCompass ? heading.value : nil,
                gyroHeading: sensorToggles.hasGyro ? gyroHeading.value : nil,
                magneticVariation: variation,
                compassDeviation: simulatedCompassDeviation(heading: heading.value),
                boatSpeed: previous.boatSpeed,
                depth: previous.depth,
                seaTemperature: previous.seaTemperature,
                airTemperature: previous.airTemperature,
                relativeHumidity: previous.relativeHumidity,
                airPressure: previous.airPressure,
                gpsData: previous.gpsData,
                gpsSignal: previous.gpsSignal,
                turnRate: previous.turnRate,
                logDistanceNm: previous.logDistanceNm,
                tripDistanceNm: previous.tripDistanceNm,
                navigationTarget: previous.navigationTarget
            )
        }

        if tackAnimationState != nil {
            NotificationCenter.default.post(name: Self.tackInstrumentStepNotification, object: self)
        }
    }

    // MARK: - Off-main transmit loop

    private func startSimulationTimer() {
        simulationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: simulationQueue)
        timer.schedule(
            deadline: .now(),
            repeating: Self.simulationFastTickInterval,
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            autoreleasepool {
                self?.runSimulationCycle()
            }
        }
        timer.resume()
        simulationTimer = timer
    }

    private func stopSimulationTimer() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    /// Main-thread convenience: captures config directly from `self`.
    private func captureSimulationConfig() -> SimulationConfig {
        Self.captureSimulationConfig(from: SimulationInputMirror(from: self))
    }

    private static func captureSimulationConfig(from mirror: SimulationInputMirror) -> SimulationConfig {
        SimulationConfig(
            sensorToggles: mirror.sensorToggles,
            sentenceToggles: mirror.sentenceToggles,
            interval: mirror.interval,
            sentenceIntervals: mirror.sentenceIntervals,
            weatherSourceMode: mirror.weatherSourceMode,
            latestLiveWeather: mirror.latestLiveWeather,
            boatSpeedMode: mirror.boatSpeedMode,
            boatProfile: mirror.boatProfile,
            waypointNavigation: mirror.waypointNavigation,
            tackAnimationInProgress: mirror.tackAnimationInProgress,
            talkerID: mirror.talkerID,
            perSentenceTalkerID: mirror.perSentenceTalkerID,
            depthOffsetMeters: mirror.depthOffsetMeters,
            faultInjection: mirror.faultInjection,
            mwvReferenceMode: mirror.mwvReferenceMode,
            enabledOutputEndpoints: mirror.outputEndpoints.filter(\.isEnabled)
        )
    }

    private static func syncLiveSetpointsIntoRuntime(_ runtime: inout SimulationState, from mirror: SimulationInputMirror) {
        func mergeSetpoints(from source: SimulatedValue, into target: inout SimulatedValue) {
            target.centerValue = source.centerValue
            target.offset = source.offset
            target.range = source.range
        }

        mergeSetpoints(from: mirror.twd, into: &runtime.twd)
        mergeSetpoints(from: mirror.tws, into: &runtime.tws)
        mergeSetpoints(from: mirror.speed, into: &runtime.speed)
        mergeSetpoints(from: mirror.depth, into: &runtime.depth)
        mergeSetpoints(from: mirror.seaTemp, into: &runtime.seaTemp)
        mergeSetpoints(from: mirror.airTemp, into: &runtime.airTemp)
        mergeSetpoints(from: mirror.humidity, into: &runtime.humidity)
        mergeSetpoints(from: mirror.barometer, into: &runtime.barometer)
        mergeSetpoints(from: mirror.heading, into: &runtime.heading)
        mergeSetpoints(from: mirror.gyroHeading, into: &runtime.gyroHeading)
        // Keep live TWD/TWS values in sync with UI setpoints so MWD/MWV don't
        // keep publishing a stale `value` while only `centerValue` moved.
        runtime.twd.value = mirror.twd.value ?? mirror.twd.centerValue
        runtime.tws.value = mirror.tws.value ?? mirror.tws.centerValue
        runtime.heading.value = mirror.heading.value
        runtime.gyroHeading.value = mirror.gyroHeading.value
        runtime.gpsData.latitude = mirror.gpsData.latitude
        runtime.gpsData.longitude = mirror.gpsData.longitude
        runtime.gpsData.speedOverGround = mirror.gpsData.speedOverGround
        runtime.gpsData.courseOverGround = mirror.gpsData.courseOverGround
    }

    private func applyRuntimeToMain(_ runtime: SimulationState, flushConsoleImmediately: Bool) {
        #if DEBUG
        HangProbe.tick(.apply)
        #endif
        isApplyingSimulationTick = true
        // Only write changed fields — unconditional 20 Hz assignment of every SimulatedValue
        // floods Observation and makes live sliders fight the UI update storm.
        if twd != runtime.twd { twd = runtime.twd }
        if tws != runtime.tws { tws = runtime.tws }
        if speed != runtime.speed { speed = runtime.speed }
        if depth != runtime.depth { depth = runtime.depth }
        if seaTemp != runtime.seaTemp { seaTemp = runtime.seaTemp }
        if airTemp != runtime.airTemp { airTemp = runtime.airTemp }
        if humidity != runtime.humidity { humidity = runtime.humidity }
        if barometer != runtime.barometer { barometer = runtime.barometer }
        if heading != runtime.heading { heading = runtime.heading }
        if gyroHeading != runtime.gyroHeading { gyroHeading = runtime.gyroHeading }
        if gpsData != runtime.gpsData { gpsData = runtime.gpsData }
        if latestSnapshot?.timestamp != runtime.latestSnapshot?.timestamp {
            latestSnapshot = runtime.latestSnapshot
        }
        if lastSimulationTickDate != runtime.lastSimulationTickDate {
            lastSimulationTickDate = runtime.lastSimulationTickDate
        }
        lastEmissionDates = runtime.lastEmissionDates
        pendingTransmissions = runtime.pendingTransmissions
        previousTurnReferenceHeading = runtime.previousTurnReferenceHeading
        sendRelativeWind = runtime.sendRelativeWind
        totalLogDistanceNm = runtime.totalLogDistanceNm
        totalTripDistanceNm = runtime.totalTripDistanceNm
        liveWeatherWindSpeedOffsetKt = runtime.liveWeatherWindSpeedOffsetKt
        liveWeatherWindDirectionOffsetDeg = runtime.liveWeatherWindDirectionOffsetDeg
        liveWeatherNoiseBaselineFetchDate = runtime.liveWeatherNoiseBaselineFetchDate
        isApplyingSimulationTick = false
        syncInputMirror()
        if !isTransmitting {
            scheduleDebouncedSimulationPersist()
        }

        if flushConsoleImmediately {
            flushConsoleDisplayToMain(immediate: true)
        }
    }

    /// Latest-wins UI frame after the current run-loop turn. A `Timer` on `.common`
    /// fires during MapKit/SwiftUI layout and can freeze the main thread.
    private func publishDisplayFrame() {
        #if DEBUG
        HangProbe.tick(.display)
        #endif
        runtimeApplyLock.lock()
        displayPublishWorkItem = nil
        runtimeApplyLock.unlock()

        flushPendingRuntimeApply()
        flushConsoleDisplayToMain(immediate: false)
    }

    private func scheduleApplyRuntimeToMain(_ runtime: SimulationState) {
        runtimeApplyLock.lock()
        pendingRuntimeApply = runtime
        let needsSchedule = displayPublishWorkItem == nil
        if needsSchedule {
            let work = DispatchWorkItem { [weak self] in
                self?.publishDisplayFrame()
            }
            displayPublishWorkItem = work
            runtimeApplyLock.unlock()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.displayPublishInterval,
                execute: work
            )
        } else {
            runtimeApplyLock.unlock()
        }
    }

    private func cancelDisplayPublish() {
        runtimeApplyLock.lock()
        displayPublishWorkItem?.cancel()
        displayPublishWorkItem = nil
        pendingRuntimeApply = nil
        runtimeApplyLock.unlock()
    }

    private func flushPendingRuntimeApply() {
        runtimeApplyLock.lock()
        let runtime = pendingRuntimeApply
        pendingRuntimeApply = nil
        runtimeApplyLock.unlock()

        guard let runtime, transmitRuntime != nil else { return }
        applyRuntimeToMain(runtime, flushConsoleImmediately: false)
    }

    private func scheduleConsoleDisplayFlush() {
        consoleLock.lock()
        guard consoleFlushWorkItem == nil else {
            consoleLock.unlock()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushConsoleDisplayToMain(immediate: false)
        }
        consoleFlushWorkItem = workItem
        consoleLock.unlock()

        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.consoleDisplayFlushInterval,
            execute: workItem
        )
    }

    private func flushConsoleDisplayToMain(immediate: Bool) {
        consoleLock.lock()
        consoleFlushWorkItem?.cancel()
        consoleFlushWorkItem = nil
        let buffered = consoleRecordBuffer
        consoleRecordBuffer.removeAll(keepingCapacity: true)
        consoleLock.unlock()

        guard !buffered.isEmpty else { return }

        for record in buffered {
            outputMessageRecords.append(record)
            outputMessages.append(record.sentence)
            totalSentCount += 1
        }

        if let referenceTimestamp = outputMessageRecords.last?.timestamp {
            pruneOutputMessageRecords(referenceTimestamp: referenceTimestamp)
        }

        consoleDisplayGeneration &+= 1

        consoleLock.lock()
        let hasMore = !consoleRecordBuffer.isEmpty
        consoleLock.unlock()
        if !immediate, hasMore {
            scheduleConsoleDisplayFlush()
        }
    }

    private func runTransmitSimulationCycle(at timestamp: Date) {
        guard var runtime = transmitRuntime else { return }

        guard let mirror = readInputMirror() else { return }
        Self.syncLiveSetpointsIntoRuntime(&runtime, from: mirror)
        let context = Self.captureSimulationConfig(from: mirror)

        if Thread.isMainThread {
            resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting()
        }
        flushPendingTransmissions(runtime: &runtime, at: timestamp, context: context)

        let snapshot: SimulationSnapshot
        if shouldAdvanceSimulation(runtime: runtime, at: timestamp, interval: context.interval) {
            snapshot = tickSimulation(runtime: &runtime, context: context, at: timestamp)
        } else if let latestSnapshot = runtime.latestSnapshot {
            snapshot = latestSnapshot
        } else {
            snapshot = tickSimulation(runtime: &runtime, context: context, at: timestamp)
        }

        let dueSentences = scheduledSentenceTypes(
            runtime: &runtime,
            at: timestamp,
            snapshot: snapshot,
            context: context
        )
        transmitRuntime = runtime

        if !dueSentences.isEmpty {
            // Capture mutable wind-reference toggle so the sentence builder
            // mutates the local copy instead of `self.sendRelativeWind` (data race).
            var mwvToggle = runtime.sendRelativeWind

            let schedule = SentenceScheduler.scheduleSentences(
                dueSentences: dueSentences,
                snapshot: snapshot,
                config: context,
                interval: context.interval,
                at: timestamp,
                sentenceBuilder: { [self] talkerID, type, snap in
                    buildNMEASentences(talkerID: talkerID, type: type, snapshot: snap, sendRelativeWind: &mwvToggle, config: context)
                },
                talkerIDResolver: { talkerID(for: $0, context: context) }
            )

            runtime.sendRelativeWind = mwvToggle

            dispatchScheduleResult(schedule, runtime: &runtime, endpoints: context.enabledOutputEndpoints, at: timestamp)

            if let flushTime = SentenceScheduler.staggerFlushTimestamp(
                sentenceCount: dueSentences.count, interval: context.interval, cycleTimestamp: timestamp
            ) {
                flushPendingTransmissions(runtime: &runtime, at: flushTime, context: context)
            }
        }

        transmitRuntime = runtime
        scheduleApplyRuntimeToMain(runtime)
    }

    private func shouldAdvanceSimulation(
        runtime: SimulationState,
        at timestamp: Date,
        interval: TimeInterval
    ) -> Bool {
        SimulationEngine.shouldAdvanceSimulation(state: runtime, at: timestamp, interval: interval)
    }

    private func talkerID(for sentence: NMEASentenceType, context: SimulationConfig) -> String {
        context.perSentenceTalkerID[sentence] ?? context.talkerID
    }

    private func flushPendingTransmissions(
        runtime: inout SimulationState,
        at timestamp: Date,
        context: SimulationConfig
    ) {
        let due = SimulationEngine.flushPendingTransmissions(state: &runtime, at: timestamp)
        for pending in due {
            for endpoint in context.enabledOutputEndpoints {
                send(pending.sentence, to: endpoint)
            }
            recordOutputMessage(pending.sentence, timestamp: timestamp)
        }
    }

    private func scheduledSentenceTypes(
        runtime: inout SimulationState,
        at timestamp: Date,
        snapshot: SimulationSnapshot,
        context: SimulationConfig
    ) -> [NMEASentenceType] {
        SimulationEngine.scheduledSentenceTypes(
            state: &runtime,
            at: timestamp,
            snapshot: snapshot,
            config: context
        )
    }

    private func tickSimulation(
        runtime: inout SimulationState,
        context: SimulationConfig,
        at timestamp: Date
    ) -> SimulationSnapshot {
        // Dispatch live weather refresh to main thread since it accesses
        // @Observable properties and creates async Tasks.
        if context.weatherSourceMode == .liveWeather {
            DispatchQueue.main.async { [weak self] in
                self?.triggerLiveWeatherRefreshIfNeeded(at: timestamp)
            }
        }
        return SimulationEngine.tickSimulation(
            state: &runtime,
            config: context,
            at: timestamp,
            liveWeatherValueGenerator: generateLiveWeatherValue(base:jitter:range:wraps:)
        )
    }

    private func appendHistoryEventOnMain(
        endpointID: UUID? = nil,
        level: TransportStatusLevel,
        category: TransportHistoryEvent.Category,
        message: String,
        timestamp: Date = .now
    ) {
        if Thread.isMainThread {
            appendHistoryEvent(
                endpointID: endpointID,
                level: level,
                category: category,
                message: message,
                timestamp: timestamp
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendHistoryEvent(
                    endpointID: endpointID,
                    level: level,
                    category: category,
                    message: message,
                    timestamp: timestamp
                )
            }
        }
    }

    private func mapDashboardBearingBeforeFirstSnapshot() -> Double {
        if sensorToggles.hasGyro {
            return normalizeAngle(gyroHeading.value ?? gyroHeading.centerValue)
        }
        if sensorToggles.hasCompass {
            return normalizeAngle(heading.value ?? heading.centerValue)
        }
        return normalizeAngle(gpsData.courseOverGround)
    }
}

// MARK: - Interlock Helpers

extension NMEASimulator {

    /// Clockwise degrees for map arrow and heading leg: matches the dashboard heading sliders — true heading from gyro when present, otherwise **magnetic** heading without applying simulated chart variation (NMEA still uses variation for true-heading sentences).
    ///
    /// Always reads **live** `gyroHeading` / `heading` / GPS COG, not `latestSnapshot`, so UI such as tack animation updates while idle (snapshot is only refreshed on transmit ticks).
    var geographicBearingDegreesForMap: Double {
        mapDashboardBearingBeforeFirstSnapshot()
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

    /// Whether a tack animation is currently driving heading / gyro.
    var isTackInProgress: Bool {
        tackAnimationState != nil
    }

    /// Tack needs wind direction and at least one heading source (gyro and/or compass).
    var canExecuteTackManeuver: Bool {
        sensorToggles.hasAnemometer && (sensorToggles.hasGyro || sensorToggles.hasCompass)
    }

    /// Animates true heading through the shortest path onto the opposite close-hauled tack using the selected boat profile’s optimal upwind angle.
    func beginTackManeuver() {
        guard canExecuteTackManeuver else { return }

        let run: () -> Void = { [weak self] in
            guard let self else { return }
            self.tackAnimationTimer?.invalidate()
            self.tackAnimationTimer = nil

            let twsSample = self.tws.value ?? self.tws.centerValue
            let optimal = self.boatProfile.optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: twsSample)
            let twdDeg = normalizeAngle(self.twd.value ?? self.twd.centerValue)

            let variation = self.simulatedMagneticVariation(for: self.gpsData, at: Date())
            let currentTrue = self.resolvedTrueHeading(
                magneticHeading: self.heading.value,
                gyroHeading: self.gyroHeading.value,
                variation: variation
            ) ?? normalizeAngle(self.gpsData.courseOverGround)

            let portCloseHauled = normalizeAngle(twdDeg + optimal)
            let stbdCloseHauled = normalizeAngle(twdDeg - optimal)

            let distToPort = abs(calculateShortestRotation(from: currentTrue, to: portCloseHauled))
            let distToStbd = abs(calculateShortestRotation(from: currentTrue, to: stbdCloseHauled))
            let targetTrue = distToPort <= distToStbd ? stbdCloseHauled : portCloseHauled

            let turnSize = abs(calculateShortestRotation(from: currentTrue, to: targetTrue))
            guard turnSize > 0.5 else { return }

            let duration = (6 + turnSize / 18 * 10).clamped(to: 6...20)
            self.tackAnimationState = TackAnimationState(
                startDate: Date(),
                duration: duration,
                fromTrueHeading: currentTrue,
                toTrueHeading: targetTrue
            )
            self.applySimulatedTrueHeading(currentTrue, at: Date())
            self.scheduleTackTimer()
        }

        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }
}
// MARK: - TransportManagerDelegate

extension NMEASimulator: TransportManagerDelegate {
    func transportManager(_ manager: TransportManager, didUpdateStatus status: OutputEndpointStatus) {
        if Thread.isMainThread {
            recordTransportStatus(status)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.recordTransportStatus(status)
            }
        }
    }

    func transportManager(_ manager: TransportManager, didEmitHistoryEvent endpointID: UUID?, level: TransportStatusLevel, category: TransportHistoryEvent.Category, message: String, timestamp: Date) {
        if Thread.isMainThread {
            appendHistoryEvent(endpointID: endpointID, level: level, category: category, message: message, timestamp: timestamp)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendHistoryEvent(endpointID: endpointID, level: level, category: category, message: message, timestamp: timestamp)
            }
        }
    }
}

