import Foundation
import Network
import Observation
import CoreLocation

@Observable
class NMEASimulator {

    /// Same interval as `scheduleTackTimer` (60 Hz). UI can use short linear motion aligned to tack steps.
    static let tackAnimationTickInterval: TimeInterval = 1.0 / 60.0

    /// Internal scheduler cadence while transmitting; decoupled from the user-facing Send Interval.
    private static let simulationFastTickInterval: TimeInterval = 0.05

    /// Throttle console / stats `@Observable` churn while transmitting (see `recordOutputMessage`).
    private static let consoleDisplayFlushInterval: TimeInterval = 0.1

    private static let simulationValuePersistDebounceInterval: TimeInterval = 5.0

    /// Posted on the main thread after each tack heading update (see `applySimulatedTrueHeading`). Wind/compass use this instead of SwiftUI `onChange` so 60 Hz steps are not coalesced or deferred.
    static let tackInstrumentStepNotification = Notification.Name("MarineSimulator.NMEASimulator.tackInstrumentStep")

    private struct PendingTransmission {
        let sentence: String
        let dueDate: Date
    }

    /// Mutable simulation state owned by the fast transmit queue while `isTransmitting`.
    private struct TransmitRuntime {
        var lastSimulationTickDate: Date?
        var lastEmissionDates: [NMEASentenceType: Date] = [:]
        var pendingTransmissions: [PendingTransmission] = []
        var previousTurnReferenceHeading: Double?
        var sendRelativeWind = true
        var totalLogDistanceNm: Double = 0
        var totalTripDistanceNm: Double = 0
        var liveWeatherWindSpeedOffsetKt: Double = 0
        var liveWeatherWindDirectionOffsetDeg: Double = 0
        var liveWeatherNoiseBaselineFetchDate: Date?
        var gpsData: GPSData
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
        var latestSnapshot: SimulationSnapshot?

        init(from simulator: NMEASimulator) {
            gpsData = simulator.gpsData
            twd = simulator.twd
            tws = simulator.tws
            speed = simulator.speed
            depth = simulator.depth
            seaTemp = simulator.seaTemp
            airTemp = simulator.airTemp
            humidity = simulator.humidity
            barometer = simulator.barometer
            heading = simulator.heading
            gyroHeading = simulator.gyroHeading
            latestSnapshot = simulator.latestSnapshot
            liveWeatherWindSpeedOffsetKt = simulator.liveWeatherWindSpeedOffsetKt
            liveWeatherWindDirectionOffsetDeg = simulator.liveWeatherWindDirectionOffsetDeg
            liveWeatherNoiseBaselineFetchDate = simulator.liveWeatherNoiseBaselineFetchDate
        }
    }

    private enum PersistenceKeys {
        static let simulatorSettings = "marine_simulator.settings"
    }

    private let userDefaults: UserDefaults
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

    private let udpClient = UDPClient()
    private let tcpClient = TCPClient()
    @ObservationIgnored private let simulationQueue = DispatchQueue(label: "com.marinesimulator.simulation", qos: .userInitiated)
    @ObservationIgnored private var simulationTimer: DispatchSourceTimer?

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
    private var endpointConnectionSignatures: [UUID: String] = [:]
    private var pendingTransmissions: [PendingTransmission] = []
    private var simulationPersistWorkItem: DispatchWorkItem?
    @ObservationIgnored private var liveWeatherTask: Task<Bool, Never>?
    /// Authoritative engine fields while the fast transmit timer runs off the main thread.
    @ObservationIgnored private var transmitRuntime: TransmitRuntime?
    @ObservationIgnored private var consoleRecordBuffer: [OutputMessageRecord] = []
    @ObservationIgnored private var consoleFlushWorkItem: DispatchWorkItem?

    /// Mean-reverting offsets around the last live-weather snapshot (OU-style; small, smooth gusts).
    private var liveWeatherWindSpeedOffsetKt: Double = 0
    private var liveWeatherWindDirectionOffsetDeg: Double = 0
    private var liveWeatherNoiseBaselineFetchDate: Date?

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

    init(
        userDefaults: UserDefaults = .standard,
        weatherService: any WeatherService = GlobalFallbackWeatherService()
    ) {
        isRestoringSettings = true
        self.userDefaults = userDefaults
        self.weatherService = weatherService
        sentenceIntervals = Self.defaultSentenceIntervals
        perSentenceTalkerID = Self.defaultTalkerIDs
        tcpClient.onStateChange = { [weak self] endpoint, state in
            self?.handleTCPStateUpdate(state, for: endpoint)
        }
        loadPersistedSettings()
        normalizeOutputEndpoints()
        isRestoringSettings = false
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
        consoleRecordBuffer.removeAll()
        consoleDisplayGeneration &+= 1
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
        outputMessageRecords + consoleRecordBuffer
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

        simulationQueue.async { [weak self] in
            guard let self else { return }
            self.transmitRuntime = TransmitRuntime(from: self)
            self.startSimulationTimer()
            self.runSimulationCycle()
        }
    }

    func stopSimulation() {
        let wasRunning = isTransmitting || simulationTimer != nil
        isTransmitting = false
        stopSimulationTimer()
        simulationPersistWorkItem?.cancel()
        simulationPersistWorkItem = nil
        consoleFlushWorkItem?.cancel()
        consoleFlushWorkItem = nil

        if wasRunning {
            var runtimeToApply: TransmitRuntime?
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
        endpointConnectionSignatures.removeAll()
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
        let count = dueSentences.count
        guard count > 0 else { return }

        let staggerWindow = min(interval * 0.8, Double(count - 1) * 0.05)
        let gap = count > 1 ? staggerWindow / Double(count - 1) : 0

        for (index, type) in dueSentences.enumerated() {
            let delay = gap * Double(index)
            if delay < 0.001 {
                sendNMEA(type: type, snapshot: snapshot)
            } else {
                let due = timestamp.addingTimeInterval(delay)
                let sentences = applyFaultInjection(
                    to: buildNMEASentences(talkerID: talkerID(for: type), type: type, snapshot: snapshot),
                    for: type,
                    at: snapshot.timestamp
                )
                for sentence in sentences {
                    pendingTransmissions.append(PendingTransmission(sentence: sentence, dueDate: due))
                }
            }
        }

        if count > 1 {
            flushPendingTransmissions(at: timestamp.addingTimeInterval(staggerWindow + 0.001))
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

        let deltaTime = max(0, resolvedDeltaTime(for: timestamp))
        triggerLiveWeatherRefreshIfNeeded(at: timestamp)

        if weatherSourceMode == .liveWeather {
            if let liveWeather = activeLiveWeather {
                syncLiveWeatherWindNoiseBaselineIfNeeded(fetchedAt: liveWeather.fetchedAt)
                evolveLiveWeatherWindNoise(deltaTime: deltaTime)

                if sensorToggles.hasAnemometer, let baseDir = liveWeather.trueWindDirection {
                    twd.value = normalizeAngle(baseDir + liveWeatherWindDirectionOffsetDeg)
                } else {
                    twd.value = nil
                }
                if sensorToggles.hasAnemometer, let baseKt = liveWeather.trueWindSpeedKnots {
                    tws.value = (baseKt + liveWeatherWindSpeedOffsetKt).clamped(to: SimulatedValueType.windSpeed.defaultRange)
                } else {
                    tws.value = nil
                }
                seaTemp.value = sensorToggles.hasWaterTempSensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.seaSurfaceTemperatureCelsius,
                        jitter: 0.3,
                        range: SimulatedValueType.seaTemp.defaultRange,
                        wraps: false
                    )
                    : nil
                airTemp.value = sensorToggles.hasAirTempSensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.airTemperatureCelsius,
                        jitter: 0.4,
                        range: SimulatedValueType.airTemp.defaultRange,
                        wraps: false
                    )
                    : nil
                humidity.value = sensorToggles.hasHumidtySensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.relativeHumidityPercent,
                        jitter: 1.8,
                        range: SimulatedValueType.humidity.defaultRange,
                        wraps: false
                    )
                    : nil
                barometer.value = sensorToggles.hasBarometer
                    ? generateLiveWeatherValue(
                        base: liveWeather.airPressureHectopascals,
                        jitter: 0.8,
                        range: SimulatedValueType.barometer.defaultRange,
                        wraps: false
                    )
                    : nil
            } else {
                twd.value = nil
                tws.value = nil
                seaTemp.value = nil
                airTemp.value = nil
                humidity.value = nil
                barometer.value = nil
            }
        } else {
            twd.value = twd.generateRandomValue(shouldGenerate: sensorToggles.hasAnemometer)
            tws.value = tws.generateRandomValue(shouldGenerate: sensorToggles.hasAnemometer)
            seaTemp.value = seaTemp.generateRandomValue(shouldGenerate: sensorToggles.hasWaterTempSensor)
            airTemp.value = airTemp.generateRandomValue(shouldGenerate: sensorToggles.hasAirTempSensor)
            humidity.value = humidity.generateRandomValue(shouldGenerate: sensorToggles.hasHumidtySensor)
            barometer.value = barometer.generateRandomValue(shouldGenerate: sensorToggles.hasBarometer)
        }

        if tackAnimationState == nil {
            if sensorToggles.hasGyro {
                gyroHeading.value = gyroHeading.generateRandomValue(shouldGenerate: true)
                if sensorToggles.hasCompass {
                    // Gyro is the steering source when enabled; derive magnetic for HDG/TWA consistency.
                    let variation = simulatedMagneticVariation(for: gpsData, at: timestamp)
                    let trueHeading = gyroHeading.value ?? gyroHeading.centerValue
                    heading.value = normalizeAngle(trueHeading - variation)
                }
            } else {
                heading.value = heading.generateRandomValue(shouldGenerate: sensorToggles.hasCompass)
            }
        }
        depth.value = depth.generateRandomValue(shouldGenerate: sensorToggles.hasEchoSounder)

        let magneticVariation = simulatedMagneticVariation(for: gpsData, at: timestamp)
        let boatTrueHeading = resolvedSteeringTrueHeading(variation: magneticVariation)

        if boatSpeedMode == .estimated {
            speed.value = estimatedBoatSpeed(trueHeading: boatTrueHeading)
        } else {
            speed.value = speed.generateRandomValue(shouldGenerate: sensorToggles.hasSpeedLog)
        }

        let waterSpeed = speed.value ?? gpsData.speedOverGround
        let movement = simulatedMovement(waterSpeed: waterSpeed, trueHeading: boatTrueHeading, at: timestamp, gpsData: gpsData)

        if sensorToggles.hasGPS && deltaTime > 0 {
            gpsData.updatePosition(deltaTime: deltaTime, sog: movement.speedOverGround, cog: movement.courseOverGround)
        }

        if sensorToggles.hasSpeedLog {
            totalLogDistanceNm += max(0, waterSpeed) * deltaTime / 3600
            totalTripDistanceNm += max(0, waterSpeed) * deltaTime / 3600
        }

        let turnRate = computedTurnRate(currentHeading: boatTrueHeading, deltaTime: deltaTime)
        let compassDeviation = simulatedCompassDeviation(heading: heading.value)
        let gpsSignal = simulatedGPSSignal(for: gpsData, at: timestamp)

        let navTarget: NavigationTarget? = waypointNavigation.isActive ? NavigationTarget(
            originName: waypointNavigation.originName,
            destinationName: waypointNavigation.destinationName,
            originLatitude: waypointNavigation.originLatitude,
            originLongitude: waypointNavigation.originLongitude,
            destinationLatitude: waypointNavigation.destinationLatitude,
            destinationLongitude: waypointNavigation.destinationLongitude,
            arrivalRadiusNm: waypointNavigation.arrivalRadiusNm
        ) : nil

        let snapshot = SimulationSnapshot(
            timestamp: timestamp,
            windDirectionTrue: twd.value,
            windSpeedTrue: tws.value,
            magneticHeading: heading.value,
            gyroHeading: gyroHeading.value,
            magneticVariation: magneticVariation,
            compassDeviation: compassDeviation,
            boatSpeed: speed.value,
            depth: depth.value,
            seaTemperature: seaTemp.value,
            airTemperature: airTemp.value,
            relativeHumidity: humidity.value,
            airPressure: barometer.value,
            gpsData: gpsData,
            gpsSignal: gpsSignal,
            turnRate: turnRate,
            logDistanceNm: totalLogDistanceNm,
            tripDistanceNm: totalTripDistanceNm,
            navigationTarget: navTarget
        )

        latestSnapshot = snapshot
        lastSimulationTickDate = timestamp
        return snapshot
    }

    private func sendNMEA(type: NMEASentenceType, snapshot: SimulationSnapshot) {
        let effectiveTalkerID = talkerID(for: type)
        let sentences = applyFaultInjection(
            to: buildNMEASentences(talkerID: effectiveTalkerID, type: type, snapshot: snapshot),
            for: type,
            at: snapshot.timestamp
        )
        guard !sentences.isEmpty else {
            return
        }

        for sentence in sentences {
            for endpoint in enabledOutputEndpoints() {
                send(sentence, to: endpoint)
            }

            recordOutputMessage(sentence, timestamp: snapshot.timestamp)
        }
    }

    private func scheduledSentenceTypes(at timestamp: Date, snapshot: SimulationSnapshot) -> [NMEASentenceType] {
        activeSentenceTypes(snapshot: snapshot).filter { type in
            let minimumInterval = effectiveInterval(for: type)
            guard minimumInterval > 0 else {
                lastEmissionDates[type] = timestamp
                return true
            }

            guard let lastEmission = lastEmissionDates[type] else {
                lastEmissionDates[type] = timestamp
                return true
            }

            let isDue = timestamp.timeIntervalSince(lastEmission) >= minimumInterval
            if isDue {
                lastEmissionDates[type] = timestamp
            }
            return isDue
        }
    }

    private func activeSentenceTypes(snapshot: SimulationSnapshot) -> [NMEASentenceType] {
        var types: [NMEASentenceType] = []

        if sensorToggles.hasAnemometer && sentenceToggles.shouldSendMWV {
            types.append(.mwv)
        }
        if canSendFullWindData && sentenceToggles.shouldSendMWD {
            types.append(.mwd)
        }
        if canSendFullWindData && sentenceToggles.shouldSendVPW {
            types.append(.vpw)
        }

        if sensorToggles.hasCompass && sentenceToggles.shouldSendHDG {
            types.append(.hdg)
        }
        if sensorToggles.hasGyro && sentenceToggles.shouldSendHDT {
            types.append(.hdt)
        }
        if sensorToggles.hasGyro && sentenceToggles.shouldSendROT {
            types.append(.rot)
        }

        if sensorToggles.hasEchoSounder && sentenceToggles.shouldSendDBT {
            types.append(.dbt)
        }
        if sensorToggles.hasEchoSounder && abs(depthOffsetMeters) <= 99 && sentenceToggles.shouldSendDPT {
            types.append(.dpt)
        }
        if sensorToggles.hasWaterTempSensor && sentenceToggles.shouldSendMTW {
            types.append(.mtw)
        }
        if sensorToggles.hasSpeedLog && (sensorToggles.hasCompass || sensorToggles.hasGyro) && sentenceToggles.shouldSendVHW {
            types.append(.vhw)
        }
        if (sensorToggles.hasSpeedLog || sensorToggles.hasGPS) && sentenceToggles.shouldSendVBW {
            types.append(.vbw)
        }
        if sensorToggles.hasSpeedLog && sentenceToggles.shouldSendVLW {
            types.append(.vlw)
        }

        if sensorToggles.hasGPS {
            if sentenceToggles.shouldSendRMC { types.append(.rmc) }
            if sentenceToggles.shouldSendGGA { types.append(.gga) }
            if sentenceToggles.shouldSendVTG { types.append(.vtg) }
            if sentenceToggles.shouldSendGLL { types.append(.gll) }
            if sentenceToggles.shouldSendGSA { types.append(.gsa) }
            if sentenceToggles.shouldSendGSV { types.append(.gsv) }
            if sentenceToggles.shouldSendZDA { types.append(.zda) }

            if waypointNavigation.isActive {
                if sentenceToggles.shouldSendRMB { types.append(.rmb) }
                if sentenceToggles.shouldSendXTE { types.append(.xte) }
            }
        }

        return types
    }

    private func enabledOutputEndpoints() -> [OutputEndpoint] {
        syncPrimaryOutputEndpoint()
        resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting()
        return outputEndpoints.filter(\.isEnabled)
    }

    private func send(_ sentence: String, to endpoint: OutputEndpoint) {
        switch endpoint.transport {
        case .udp:
            udpClient.send(sentence, to: endpoint) { [weak self] result in
                self?.handleTransportResult(result, for: endpoint)
            }
        case .tcp:
            tcpClient.send(sentence, to: endpoint) { [weak self] result in
                self?.handleTransportResult(result, for: endpoint)
            }
        }
    }

    private func handleTransportResult(_ result: Result<Void, NWError>, for endpoint: OutputEndpoint) {
        DispatchQueue.main.async {
            switch result {
            case .success:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .connected,
                        message: "\(endpoint.transport.rawValue.uppercased()) connected to \(endpoint.effectiveHost):\(endpoint.port)"
                    )
                )
            case .failure(let error):
                let level: TransportStatusLevel = {
                    if case .posix(.ECONNREFUSED) = error {
                        return .warning
                    }
                    if case .posix(.ECONNABORTED) = error {
                        return .warning
                    }
                    return .error
                }()

                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: level,
                        message: "\(endpoint.transport.rawValue.uppercased()) \(endpoint.effectiveHost):\(endpoint.port) - \(self.transportErrorSummary(error))"
                    )
                )
            }
        }
    }

    private func handleTCPStateUpdate(_ state: TCPClient.StateUpdate, for endpoint: OutputEndpoint) {
        DispatchQueue.main.async {
            switch state {
            case .connecting:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .idle,
                        message: "TCP connecting to \(endpoint.effectiveHost):\(endpoint.port)"
                    )
                )
            case .ready:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .connected,
                        message: "TCP connected to \(endpoint.effectiveHost):\(endpoint.port)"
                    )
                )
            case .waiting:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .warning,
                        message: "TCP waiting for \(endpoint.effectiveHost):\(endpoint.port)"
                    )
                )
            case .failed(let error, let retryAfter):
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .error,
                        message: "TCP \(endpoint.effectiveHost):\(endpoint.port) - \(self.transportErrorSummary(error)) (retry after \(retryAfter.formatted(date: .omitted, time: .standard)))"
                    )
                )
            case .cancelled:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .idle,
                        message: "TCP \(endpoint.effectiveHost):\(endpoint.port) idle"
                    )
                )
            }
        }
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

    private func transportErrorSummary(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            return "connection refused"
        case .posix(.ECONNABORTED):
            return "retry cooling down"
        case .posix(.ETIMEDOUT):
            return "timed out"
        default:
            return error.localizedDescription
        }
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
        outputEndpoints[0].isEnabled = true
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

        outputEndpoints[0].name = outputEndpoints[0].name.isEmpty ? "Primary Output" : outputEndpoints[0].name
        outputEndpoints[0].host = outputEndpoints[0].host
        outputEndpoints[0].port = outputEndpoints[0].port
        outputEndpoints[0].isEnabled = true

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
        guard !isRestoringSettings, !isApplyingSimulationTick else {
            return
        }

        persistSettings()
    }

    private func scheduleDebouncedSimulationPersist() {
        simulationPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistSettings()
        }
        simulationPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.simulationValuePersistDebounceInterval,
            execute: workItem
        )
    }

    private func shouldAdvanceSimulation(at timestamp: Date) -> Bool {
        guard let lastSimulationTickDate else {
            return true
        }
        return timestamp.timeIntervalSince(lastSimulationTickDate) >= interval
    }

    private func endpointConnectionSignature(for endpoint: OutputEndpoint) -> String {
        "\(endpoint.transport.rawValue)|\(endpoint.effectiveHost)|\(endpoint.port)"
    }

    private func resetTransportConnections() {
        udpClient.resetConnections()
        tcpClient.resetConnections()
    }

    private func resetTransportConnectionsIfTransmitting() {
        guard isTransmitting else { return }
        resetTransportConnections()
        refreshEndpointConnectionSignatures()
    }

    private func resetTransportConnectionsIfEndpointTargetsChanged(from oldEndpoints: [OutputEndpoint], to newEndpoints: [OutputEndpoint]) {
        guard isTransmitting else {
            refreshEndpointConnectionSignatures(from: newEndpoints)
            return
        }

        let oldByID = Dictionary(uniqueKeysWithValues: oldEndpoints.map { ($0.id, $0) })
        let connectionTargetChanged = newEndpoints.contains { endpoint in
            guard let previous = oldByID[endpoint.id] else {
                return false
            }
            return endpointConnectionSignature(for: previous) != endpointConnectionSignature(for: endpoint)
        }

        if connectionTargetChanged {
            resetTransportConnections()
        }
        refreshEndpointConnectionSignatures(from: newEndpoints)
    }

    private func resetTransportConnectionsIfEndpointTargetsChangedWhileTransmitting() {
        guard isTransmitting else {
            refreshEndpointConnectionSignatures()
            return
        }

        var connectionTargetChanged = false
        for endpoint in outputEndpoints {
            let signature = endpointConnectionSignature(for: endpoint)
            if endpointConnectionSignatures[endpoint.id] != signature {
                connectionTargetChanged = true
            }
            endpointConnectionSignatures[endpoint.id] = signature
        }

        let staleIDs = Set(endpointConnectionSignatures.keys).subtracting(outputEndpoints.map(\.id))
        if !staleIDs.isEmpty {
            connectionTargetChanged = true
            for staleID in staleIDs {
                endpointConnectionSignatures.removeValue(forKey: staleID)
            }
        }

        if connectionTargetChanged {
            resetTransportConnections()
        }
    }

    private func refreshEndpointConnectionSignatures(from endpoints: [OutputEndpoint]? = nil) {
        let endpoints = endpoints ?? outputEndpoints
        endpointConnectionSignatures = Dictionary(
            uniqueKeysWithValues: endpoints.map { ($0.id, endpointConnectionSignature(for: $0)) }
        )
    }

    private(set) var persistSettingsInvocationCount = 0

    private func persistSettings() {
        persistSettingsInvocationCount += 1
        do {
            let data = try JSONEncoder().encode(makeSettingsSnapshot())
            userDefaults.set(data, forKey: PersistenceKeys.simulatorSettings)
        } catch {
            print("Failed to persist simulator settings: \(error)")
        }
    }

    private func loadPersistedSettings() {
        guard let data = userDefaults.data(forKey: PersistenceKeys.simulatorSettings) else {
            return
        }

        do {
            let settings = try JSONDecoder().decode(SimulatorSettings.self, from: data)
            apply(settings: settings)
        } catch {
            print("Failed to restore simulator settings: \(error)")
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
        simulationQueue.async { [weak self] in
            guard let self else { return }
            if self.transmitRuntime == nil {
                self.transmitRuntime = TransmitRuntime(from: self)
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
            isTransmitting = false
            var runtimeToApply: TransmitRuntime?
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

    private func resolvedDeltaTime(for timestamp: Date) -> TimeInterval {
        if let lastSimulationTickDate {
            return timestamp.timeIntervalSince(lastSimulationTickDate)
        }
        return 0
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

    private func computedTurnRate(currentHeading: Double, deltaTime: TimeInterval) -> Double {
        defer {
            previousTurnReferenceHeading = currentHeading
        }

        guard deltaTime > 0, let previousTurnReferenceHeading else {
            return 0
        }

        let delta = calculateShortestRotation(from: previousTurnReferenceHeading, to: currentHeading)
        return delta / deltaTime * 60
    }

    private func simulatedMovement(waterSpeed: Double, trueHeading: Double, at timestamp: Date, gpsData: GPSData) -> (speedOverGround: Double, courseOverGround: Double) {
        let headingRadians = toRadians(trueHeading)
        let waterEast = waterSpeed * sin(headingRadians)
        let waterNorth = waterSpeed * cos(headingRadians)

        let current = simulatedCurrent(at: timestamp, gpsData: gpsData)
        let east = waterEast + current.eastKnots
        let north = waterNorth + current.northKnots

        let sog = sqrt(east * east + north * north)
        let cog = normalizeAngle(toDegrees(atan2(east, north)))
        return (sog, cog)
    }

    private func simulatedCurrent(at timestamp: Date, gpsData: GPSData) -> (eastKnots: Double, northKnots: Double) {
        // Keep COG aligned with heading until current/drift is exposed as an explicit operator control.
        _ = timestamp
        _ = gpsData
        return (eastKnots: 0, northKnots: 0)
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

    /// True heading used for dead reckoning: gyro setpoint when a gyro is enabled, otherwise magnetic + variation, else COG.
    /// Uses live setpoints (`centerValue`) when jittered `value` is not yet populated so map, movement, and sliders stay aligned.
    private func resolvedSteeringTrueHeading(variation: Double) -> Double {
        if sensorToggles.hasGyro {
            return normalizeAngle(gyroHeading.value ?? gyroHeading.centerValue)
        }

        if sensorToggles.hasCompass {
            return normalizeAngle((heading.value ?? heading.centerValue) + variation)
        }

        return normalizeAngle(gpsData.courseOverGround)
    }

    private func simulatedMagneticVariation(for gpsData: GPSData, at timestamp: Date) -> Double {
        let seasonalCycle = sin(timestamp.timeIntervalSinceReferenceDate / 86_400 / 45) * 1.8
        let geographicTrend = gpsData.longitude * 0.16 + sin(toRadians(gpsData.latitude)) * 6.5
        return max(-25, min(25, geographicTrend + seasonalCycle))
    }

    private func simulatedCompassDeviation(heading: Double?) -> Double {
        guard let heading else {
            return 0
        }

        return sin(toRadians(heading * 1.7)) * 1.2
    }

    private func simulatedGPSSignal(for gpsData: GPSData, at timestamp: Date) -> GPSSignalSnapshot {
        let timeComponent = timestamp.timeIntervalSinceReferenceDate / 90
        let latitudeComponent = sin(toRadians(gpsData.latitude))
        let longitudeComponent = cos(toRadians(gpsData.longitude))
        let visibleCount = max(8, min(12, 10 + Int(round(latitudeComponent * 1.4 + longitudeComponent * 1.2 + sin(timeComponent) * 1.1))))
        let usedCount = max(6, min(visibleCount, visibleCount - 1))
        let hdop = max(0.7, min(2.4, 1.9 - Double(usedCount - 6) * 0.18 + abs(sin(timeComponent)) * 0.25))
        let vdop = hdop + 0.4 + abs(cos(timeComponent)) * 0.18
        let pdop = sqrt(hdop * hdop + vdop * vdop)
        let altitudeMeters = 3.5 + sin(toRadians(gpsData.latitude * 3)) * 1.1 + cos(timeComponent / 2) * 0.6
        let geoidalSeparationMeters = 31 + sin(toRadians(gpsData.longitude * 2)) * 4

        return GPSSignalSnapshot(
            fixQuality: 1,
            fixMode: 3,
            selectionMode: "A",
            satellitesUsed: usedCount,
            hdop: hdop,
            vdop: vdop,
            pdop: pdop,
            altitudeMeters: altitudeMeters,
            geoidalSeparationMeters: geoidalSeparationMeters,
            satellites: simulatedSatellites(visibleCount: visibleCount, usedCount: usedCount, at: timestamp)
        )
    }

    private func simulatedSatellites(visibleCount: Int, usedCount: Int, at timestamp: Date) -> [GPSSatelliteSnapshot] {
        let prnPool = [3, 5, 7, 9, 11, 13, 15, 18, 21, 24, 27, 30, 32, 36, 38]
        let phase = timestamp.timeIntervalSinceReferenceDate / 60

        return (0..<visibleCount).map { index in
            let azimuth = Int(normalizeAngle(Double(index) * (360.0 / Double(visibleCount)) + phase * 7))
            let elevation = max(8, min(78, Int(round(22 + sin(phase + Double(index) * 0.7) * 18 + Double(index % 3) * 9))))
            let snrBase = 28 + Int(round(cos(phase / 2 + Double(index) * 0.9) * 8))
            let snr = max(22, min(48, snrBase + max(0, elevation - 20) / 8))

            return GPSSatelliteSnapshot(
                prn: prnPool[index % prnPool.count],
                elevation: elevation,
                azimuth: azimuth,
                snr: snr,
                isUsedInFix: index < usedCount
            )
        }
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
            consoleRecordBuffer.append(record)
            scheduleConsoleDisplayFlush()
            return
        }

        outputMessageRecords.append(record)
        outputMessages.append(sentence)
        totalSentCount += 1
        pruneOutputMessageRecords(referenceTimestamp: timestamp)
    }

    private func pruneOutputMessageRecords(referenceTimestamp: Date) {
        let cutoff = referenceTimestamp.addingTimeInterval(-2)
        outputMessageRecords.removeAll { $0.timestamp < cutoff }

        if outputMessageRecords.count > 100 {
            outputMessageRecords.removeFirst(outputMessageRecords.count - 100)
        }

        outputMessages = outputMessageRecords.map(\.sentence)
    }

    func sentPerSecond(at timestamp: Date = .now) -> Int {
        let windowStart = timestamp.addingTimeInterval(-1)
        let visibleCount = outputMessageRecords.filter { $0.timestamp >= windowStart }.count
        let bufferedCount = consoleRecordBuffer.filter { $0.timestamp >= windowStart }.count
        return visibleCount + bufferedCount
    }

    private func applyFaultInjection(
        to sentences: [String],
        for type: NMEASentenceType,
        at timestamp: Date
    ) -> [String] {
        guard faultInjection.isEnabled else {
            return sentences
        }

        var transmitted: [String] = []

        for sentence in sentences {
            if shouldInjectFault(rate: faultInjection.dropRate) {
                appendHistoryEvent(level: .warning, category: .fault, message: "Dropped \(type.rawValue.uppercased()) sentence")
                continue
            }

            var mutated = sentence

            if shouldInjectFault(rate: faultInjection.invalidDataRate),
               let invalidSentence = invalidatedSentence(from: mutated, type: type) {
                mutated = invalidSentence
                appendHistoryEvent(level: .warning, category: .fault, message: "Injected invalid data into \(type.rawValue.uppercased()) sentence")
            }

            if shouldInjectFault(rate: faultInjection.checksumCorruptionRate),
               let corrupted = corruptedChecksumSentence(from: mutated) {
                mutated = corrupted
                appendHistoryEvent(level: .warning, category: .fault, message: "Corrupted checksum for \(type.rawValue.uppercased()) sentence")
            }

            if shouldInjectFault(rate: faultInjection.delayRate) {
                let delayCycles = max(1, Int.random(in: 1...max(1, faultInjection.maximumDelayCycles)))
                let dueDate = timestamp.addingTimeInterval(interval * Double(delayCycles))
                pendingTransmissions.append(PendingTransmission(sentence: mutated, dueDate: dueDate))
                appendHistoryEvent(level: .warning, category: .fault, message: "Delayed \(type.rawValue.uppercased()) sentence by \(delayCycles) cycle(s)")
                continue
            }

            transmitted.append(mutated)
        }

        return transmitted
    }

    private func shouldInjectFault(rate: Double) -> Bool {
        guard faultInjection.isEnabled, rate > 0 else {
            return false
        }
        return Double.random(in: 0...1) < min(max(rate, 0), 1)
    }

    private func invalidatedSentence(from sentence: String, type: NMEASentenceType) -> String? {
        guard let payload = payload(from: sentence) else {
            return nil
        }

        let fields = payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var mutatedFields = fields

        switch type {
        case .rmc:
            guard mutatedFields.count > 2 else { return nil }
            mutatedFields[2] = "V"
        case .gll:
            guard mutatedFields.count > 6 else { return nil }
            mutatedFields[6] = "V"
        case .vtg:
            guard mutatedFields.count > 9 else { return nil }
            mutatedFields[9] = "N"
        case .gga:
            guard mutatedFields.count > 7 else { return nil }
            mutatedFields[6] = "0"
            mutatedFields[7] = "00"
        case .rot:
            guard mutatedFields.count > 2 else { return nil }
            mutatedFields[2] = "V"
        default:
            return nil
        }

        return addChecksum(to: "$" + mutatedFields.joined(separator: ","))
    }

    private func corruptedChecksumSentence(from sentence: String) -> String? {
        guard let starIndex = sentence.firstIndex(of: "*") else {
            return nil
        }

        let prefix = sentence[..<sentence.index(after: starIndex)]
        return "\(prefix)00\r\n"
    }

    private func payload(from sentence: String) -> String? {
        guard sentence.first == "$", let starIndex = sentence.firstIndex(of: "*") else {
            return nil
        }

        let startIndex = sentence.index(after: sentence.startIndex)
        return String(sentence[startIndex..<starIndex])
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
                magneticHeading: heading.value,
                gyroHeading: gyroHeading.value,
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

    private func estimatedBoatSpeed(trueHeading: Double) -> Double? {
        guard sensorToggles.hasSpeedLog, let trueWindSpeed = tws.value else {
            return nil
        }

        let trueWindDirection = twd.value ?? gpsData.courseOverGround
        let trueWindAngle = abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))
        let baseSpeed = boatProfile.estimatedBoatSpeed(
            trueWindSpeedKnots: trueWindSpeed,
            trueWindAngleDegrees: trueWindAngle
        )

        let seaStatePenalty = weatherSourceMode == .liveWeather ? 0.96 : 1.0
        let variationPenalty = max(0.88, 1.0 - (speed.offset / 100))
        return (baseSpeed * seaStatePenalty * variationPenalty).clamped(to: SimulatedValueType.speedLog.defaultRange)
    }

    // MARK: - Off-main transmit loop

    private struct LiveCycleContext {
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
        let talkerID: String
        let perSentenceTalkerID: [NMEASentenceType: String]
        let faultInjection: FaultInjectionSettings
        let mwvReferenceMode: MWVReferenceMode
    }

    private func startSimulationTimer() {
        simulationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: simulationQueue)
        timer.schedule(
            deadline: .now(),
            repeating: Self.simulationFastTickInterval,
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            self?.runSimulationCycle()
        }
        timer.resume()
        simulationTimer = timer
    }

    private func stopSimulationTimer() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    private func captureLiveCycleContext() -> LiveCycleContext {
        LiveCycleContext(
            sensorToggles: sensorToggles,
            sentenceToggles: sentenceToggles,
            interval: interval,
            sentenceIntervals: sentenceIntervals,
            weatherSourceMode: weatherSourceMode,
            latestLiveWeather: latestLiveWeather,
            boatSpeedMode: boatSpeedMode,
            boatProfile: boatProfile,
            waypointNavigation: waypointNavigation,
            tackAnimationInProgress: tackAnimationState != nil,
            talkerID: talkerID,
            perSentenceTalkerID: perSentenceTalkerID,
            faultInjection: faultInjection,
            mwvReferenceMode: mwvReferenceMode
        )
    }

    private func syncLiveSetpointsIntoRuntime(_ runtime: inout TransmitRuntime) {
        func mergeSetpoints(from source: SimulatedValue, into target: inout SimulatedValue) {
            target.centerValue = source.centerValue
            target.offset = source.offset
            target.range = source.range
        }

        mergeSetpoints(from: twd, into: &runtime.twd)
        mergeSetpoints(from: tws, into: &runtime.tws)
        mergeSetpoints(from: speed, into: &runtime.speed)
        mergeSetpoints(from: depth, into: &runtime.depth)
        mergeSetpoints(from: seaTemp, into: &runtime.seaTemp)
        mergeSetpoints(from: airTemp, into: &runtime.airTemp)
        mergeSetpoints(from: humidity, into: &runtime.humidity)
        mergeSetpoints(from: barometer, into: &runtime.barometer)
        mergeSetpoints(from: heading, into: &runtime.heading)
        mergeSetpoints(from: gyroHeading, into: &runtime.gyroHeading)
        runtime.heading.value = heading.value
        runtime.gyroHeading.value = gyroHeading.value
        runtime.gpsData.speedOverGround = gpsData.speedOverGround
        runtime.gpsData.courseOverGround = gpsData.courseOverGround
    }

    private func applyRuntimeToMain(_ runtime: TransmitRuntime, flushConsoleImmediately: Bool) {
        isApplyingSimulationTick = true
        twd = runtime.twd
        tws = runtime.tws
        speed = runtime.speed
        depth = runtime.depth
        seaTemp = runtime.seaTemp
        airTemp = runtime.airTemp
        humidity = runtime.humidity
        barometer = runtime.barometer
        heading = runtime.heading
        gyroHeading = runtime.gyroHeading
        gpsData = runtime.gpsData
        latestSnapshot = runtime.latestSnapshot
        lastSimulationTickDate = runtime.lastSimulationTickDate
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
        scheduleDebouncedSimulationPersist()

        if flushConsoleImmediately {
            flushConsoleDisplayToMain(immediate: true)
        }
    }

    private func scheduleApplyRuntimeToMain(_ runtime: TransmitRuntime) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.transmitRuntime != nil else { return }
            self.applyRuntimeToMain(runtime, flushConsoleImmediately: false)
        }
    }

    private func scheduleConsoleDisplayFlush() {
        guard consoleFlushWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushConsoleDisplayToMain(immediate: false)
        }
        consoleFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.consoleDisplayFlushInterval,
            execute: workItem
        )
    }

    private func flushConsoleDisplayToMain(immediate: Bool) {
        consoleFlushWorkItem?.cancel()
        consoleFlushWorkItem = nil

        guard !consoleRecordBuffer.isEmpty else { return }

        let buffered = consoleRecordBuffer
        consoleRecordBuffer.removeAll(keepingCapacity: true)

        for record in buffered {
            outputMessageRecords.append(record)
            outputMessages.append(record.sentence)
            totalSentCount += 1
        }

        if let referenceTimestamp = outputMessageRecords.last?.timestamp {
            pruneOutputMessageRecords(referenceTimestamp: referenceTimestamp)
        }

        consoleDisplayGeneration &+= 1

        if !immediate, !consoleRecordBuffer.isEmpty {
            scheduleConsoleDisplayFlush()
        }
    }

    private func runTransmitSimulationCycle(at timestamp: Date) {
        guard var runtime = transmitRuntime else { return }

        syncLiveSetpointsIntoRuntime(&runtime)
        let context = captureLiveCycleContext()

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
        let count = dueSentences.count
        transmitRuntime = runtime

        if count > 0 {
            let staggerWindow = min(context.interval * 0.8, Double(count - 1) * 0.05)
            let gap = count > 1 ? staggerWindow / Double(count - 1) : 0

            for (index, type) in dueSentences.enumerated() {
                let delay = gap * Double(index)
                if delay < 0.001 {
                    sendNMEA(type: type, snapshot: snapshot)
                } else {
                    let due = timestamp.addingTimeInterval(delay)
                    let sentences = applyFaultInjection(
                        to: buildNMEASentences(
                            talkerID: talkerID(for: type, context: context),
                            type: type,
                            snapshot: snapshot
                        ),
                        for: type,
                        at: snapshot.timestamp,
                        context: context,
                        runtime: &runtime
                    )
                    for sentence in sentences {
                        runtime.pendingTransmissions.append(PendingTransmission(sentence: sentence, dueDate: due))
                    }
                }
            }

            if count > 1 {
                flushPendingTransmissions(
                    runtime: &runtime,
                    at: timestamp.addingTimeInterval(staggerWindow + 0.001),
                    context: context
                )
            }
        }

        transmitRuntime = runtime
        scheduleApplyRuntimeToMain(runtime)
    }

    private func shouldAdvanceSimulation(
        runtime: TransmitRuntime,
        at timestamp: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let lastSimulationTickDate = runtime.lastSimulationTickDate else {
            return true
        }
        return timestamp.timeIntervalSince(lastSimulationTickDate) >= interval
    }

    private func talkerID(for sentence: NMEASentenceType, context: LiveCycleContext) -> String {
        context.perSentenceTalkerID[sentence] ?? context.talkerID
    }

    private func effectiveInterval(
        for sentence: NMEASentenceType,
        context: LiveCycleContext
    ) -> TimeInterval {
        if let configured = context.sentenceIntervals[sentence] {
            return configured
        }
        return context.interval
    }

    private func flushPendingTransmissions(
        runtime: inout TransmitRuntime,
        at timestamp: Date,
        context: LiveCycleContext
    ) {
        let due = runtime.pendingTransmissions.filter { $0.dueDate <= timestamp }
        runtime.pendingTransmissions.removeAll { $0.dueDate <= timestamp }

        for pending in due {
            for endpoint in enabledOutputEndpoints() {
                send(pending.sentence, to: endpoint)
            }
            recordOutputMessage(pending.sentence, timestamp: timestamp)
        }
    }

    private func scheduledSentenceTypes(
        runtime: inout TransmitRuntime,
        at timestamp: Date,
        snapshot: SimulationSnapshot,
        context: LiveCycleContext
    ) -> [NMEASentenceType] {
        activeSentenceTypes(snapshot: snapshot, context: context).filter { type in
            let minimumInterval = effectiveInterval(for: type, context: context)
            guard minimumInterval > 0 else {
                runtime.lastEmissionDates[type] = timestamp
                return true
            }

            guard let lastEmission = runtime.lastEmissionDates[type] else {
                runtime.lastEmissionDates[type] = timestamp
                return true
            }

            let isDue = timestamp.timeIntervalSince(lastEmission) >= minimumInterval
            if isDue {
                runtime.lastEmissionDates[type] = timestamp
            }
            return isDue
        }
    }

    private func activeSentenceTypes(
        snapshot: SimulationSnapshot,
        context: LiveCycleContext
    ) -> [NMEASentenceType] {
        var types: [NMEASentenceType] = []

        if context.sensorToggles.hasAnemometer && context.sentenceToggles.shouldSendMWV {
            types.append(.mwv)
        }
        if canSendFullWindData(context: context) && context.sentenceToggles.shouldSendMWD {
            types.append(.mwd)
        }
        if canSendFullWindData(context: context) && context.sentenceToggles.shouldSendVPW {
            types.append(.vpw)
        }

        if context.sensorToggles.hasCompass && context.sentenceToggles.shouldSendHDG {
            types.append(.hdg)
        }
        if context.sensorToggles.hasGyro && context.sentenceToggles.shouldSendHDT {
            types.append(.hdt)
        }
        if context.sensorToggles.hasGyro && context.sentenceToggles.shouldSendROT {
            types.append(.rot)
        }

        if context.sensorToggles.hasEchoSounder && context.sentenceToggles.shouldSendDBT {
            types.append(.dbt)
        }
        if context.sensorToggles.hasEchoSounder && abs(depthOffsetMeters) <= 99 && context.sentenceToggles.shouldSendDPT {
            types.append(.dpt)
        }
        if context.sensorToggles.hasWaterTempSensor && context.sentenceToggles.shouldSendMTW {
            types.append(.mtw)
        }
        if context.sensorToggles.hasSpeedLog && (context.sensorToggles.hasCompass || context.sensorToggles.hasGyro) && context.sentenceToggles.shouldSendVHW {
            types.append(.vhw)
        }
        if (context.sensorToggles.hasSpeedLog || context.sensorToggles.hasGPS) && context.sentenceToggles.shouldSendVBW {
            types.append(.vbw)
        }
        if context.sensorToggles.hasSpeedLog && context.sentenceToggles.shouldSendVLW {
            types.append(.vlw)
        }

        if context.sensorToggles.hasGPS {
            if context.sentenceToggles.shouldSendRMC { types.append(.rmc) }
            if context.sentenceToggles.shouldSendGGA { types.append(.gga) }
            if context.sentenceToggles.shouldSendVTG { types.append(.vtg) }
            if context.sentenceToggles.shouldSendGLL { types.append(.gll) }
            if context.sentenceToggles.shouldSendGSA { types.append(.gsa) }
            if context.sentenceToggles.shouldSendGSV { types.append(.gsv) }
            if context.sentenceToggles.shouldSendZDA { types.append(.zda) }

            if context.waypointNavigation.isActive {
                if context.sentenceToggles.shouldSendRMB { types.append(.rmb) }
                if context.sentenceToggles.shouldSendXTE { types.append(.xte) }
            }
        }

        return types
    }

    private func canSendFullWindData(context: LiveCycleContext) -> Bool {
        let hasAnemometer = context.sensorToggles.hasAnemometer
        let hasBoatSpeed = context.sensorToggles.hasSpeedLog || context.sensorToggles.hasGPS
        let hasTrueHeading = context.sensorToggles.hasGyro || context.sensorToggles.hasCompass
        return hasAnemometer && hasBoatSpeed && hasTrueHeading
    }

    private func tickSimulation(
        runtime: inout TransmitRuntime,
        context: LiveCycleContext,
        at timestamp: Date
    ) -> SimulationSnapshot {
        let deltaTime: TimeInterval = {
            if let lastSimulationTickDate = runtime.lastSimulationTickDate {
                return max(0, timestamp.timeIntervalSince(lastSimulationTickDate))
            }
            return 0
        }()

        triggerLiveWeatherRefreshIfNeeded(at: timestamp)

        if context.weatherSourceMode == .liveWeather {
            if let liveWeather = context.latestLiveWeather {
                syncLiveWeatherWindNoiseBaselineIfNeeded(
                    runtime: &runtime,
                    fetchedAt: liveWeather.fetchedAt
                )
                evolveLiveWeatherWindNoise(runtime: &runtime, deltaTime: deltaTime)

                if context.sensorToggles.hasAnemometer, let baseDir = liveWeather.trueWindDirection {
                    runtime.twd.value = normalizeAngle(baseDir + runtime.liveWeatherWindDirectionOffsetDeg)
                } else {
                    runtime.twd.value = nil
                }
                if context.sensorToggles.hasAnemometer, let baseKt = liveWeather.trueWindSpeedKnots {
                    runtime.tws.value = (baseKt + runtime.liveWeatherWindSpeedOffsetKt)
                        .clamped(to: SimulatedValueType.windSpeed.defaultRange)
                } else {
                    runtime.tws.value = nil
                }
                runtime.seaTemp.value = context.sensorToggles.hasWaterTempSensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.seaSurfaceTemperatureCelsius,
                        jitter: 0.3,
                        range: SimulatedValueType.seaTemp.defaultRange,
                        wraps: false
                    )
                    : nil
                runtime.airTemp.value = context.sensorToggles.hasAirTempSensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.airTemperatureCelsius,
                        jitter: 0.4,
                        range: SimulatedValueType.airTemp.defaultRange,
                        wraps: false
                    )
                    : nil
                runtime.humidity.value = context.sensorToggles.hasHumidtySensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.relativeHumidityPercent,
                        jitter: 1.8,
                        range: SimulatedValueType.humidity.defaultRange,
                        wraps: false
                    )
                    : nil
                runtime.barometer.value = context.sensorToggles.hasBarometer
                    ? generateLiveWeatherValue(
                        base: liveWeather.airPressureHectopascals,
                        jitter: 0.8,
                        range: SimulatedValueType.barometer.defaultRange,
                        wraps: false
                    )
                    : nil
            } else {
                runtime.twd.value = nil
                runtime.tws.value = nil
                runtime.seaTemp.value = nil
                runtime.airTemp.value = nil
                runtime.humidity.value = nil
                runtime.barometer.value = nil
            }
        } else {
            runtime.twd.value = runtime.twd.generateRandomValue(shouldGenerate: context.sensorToggles.hasAnemometer)
            runtime.tws.value = runtime.tws.generateRandomValue(shouldGenerate: context.sensorToggles.hasAnemometer)
            runtime.seaTemp.value = runtime.seaTemp.generateRandomValue(shouldGenerate: context.sensorToggles.hasWaterTempSensor)
            runtime.airTemp.value = runtime.airTemp.generateRandomValue(shouldGenerate: context.sensorToggles.hasAirTempSensor)
            runtime.humidity.value = runtime.humidity.generateRandomValue(shouldGenerate: context.sensorToggles.hasHumidtySensor)
            runtime.barometer.value = runtime.barometer.generateRandomValue(shouldGenerate: context.sensorToggles.hasBarometer)
        }

        if !context.tackAnimationInProgress {
            if context.sensorToggles.hasGyro {
                runtime.gyroHeading.value = runtime.gyroHeading.generateRandomValue(shouldGenerate: true)
                if context.sensorToggles.hasCompass {
                    let variation = simulatedMagneticVariation(for: runtime.gpsData, at: timestamp)
                    let trueHeading = runtime.gyroHeading.value ?? runtime.gyroHeading.centerValue
                    runtime.heading.value = normalizeAngle(trueHeading - variation)
                }
            } else {
                runtime.heading.value = runtime.heading.generateRandomValue(shouldGenerate: context.sensorToggles.hasCompass)
            }
        }
        runtime.depth.value = runtime.depth.generateRandomValue(shouldGenerate: context.sensorToggles.hasEchoSounder)

        let magneticVariation = simulatedMagneticVariation(for: runtime.gpsData, at: timestamp)
        let boatTrueHeading = resolvedSteeringTrueHeading(
            runtime: runtime,
            context: context,
            variation: magneticVariation
        )

        if context.boatSpeedMode == .estimated {
            runtime.speed.value = estimatedBoatSpeed(
                trueHeading: boatTrueHeading,
                runtime: runtime,
                context: context
            )
        } else {
            runtime.speed.value = runtime.speed.generateRandomValue(shouldGenerate: context.sensorToggles.hasSpeedLog)
        }

        let waterSpeed = runtime.speed.value ?? runtime.gpsData.speedOverGround
        let movement = simulatedMovement(
            waterSpeed: waterSpeed,
            trueHeading: boatTrueHeading,
            at: timestamp,
            gpsData: runtime.gpsData
        )

        if context.sensorToggles.hasGPS && deltaTime > 0 {
            runtime.gpsData.updatePosition(
                deltaTime: deltaTime,
                sog: movement.speedOverGround,
                cog: movement.courseOverGround
            )
        }

        if context.sensorToggles.hasSpeedLog {
            runtime.totalLogDistanceNm += max(0, waterSpeed) * deltaTime / 3600
            runtime.totalTripDistanceNm += max(0, waterSpeed) * deltaTime / 3600
        }

        let turnRate = computedTurnRate(
            currentHeading: boatTrueHeading,
            deltaTime: deltaTime,
            previousReference: &runtime.previousTurnReferenceHeading
        )
        let compassDeviation = simulatedCompassDeviation(heading: runtime.heading.value)
        let gpsSignal = simulatedGPSSignal(for: runtime.gpsData, at: timestamp)

        let navTarget: NavigationTarget? = context.waypointNavigation.isActive ? NavigationTarget(
            originName: context.waypointNavigation.originName,
            destinationName: context.waypointNavigation.destinationName,
            originLatitude: context.waypointNavigation.originLatitude,
            originLongitude: context.waypointNavigation.originLongitude,
            destinationLatitude: context.waypointNavigation.destinationLatitude,
            destinationLongitude: context.waypointNavigation.destinationLongitude,
            arrivalRadiusNm: context.waypointNavigation.arrivalRadiusNm
        ) : nil

        let snapshot = SimulationSnapshot(
            timestamp: timestamp,
            windDirectionTrue: runtime.twd.value,
            windSpeedTrue: runtime.tws.value,
            magneticHeading: runtime.heading.value,
            gyroHeading: runtime.gyroHeading.value,
            magneticVariation: magneticVariation,
            compassDeviation: compassDeviation,
            boatSpeed: runtime.speed.value,
            depth: runtime.depth.value,
            seaTemperature: runtime.seaTemp.value,
            airTemperature: runtime.airTemp.value,
            relativeHumidity: runtime.humidity.value,
            airPressure: runtime.barometer.value,
            gpsData: runtime.gpsData,
            gpsSignal: gpsSignal,
            turnRate: turnRate,
            logDistanceNm: runtime.totalLogDistanceNm,
            tripDistanceNm: runtime.totalTripDistanceNm,
            navigationTarget: navTarget
        )

        runtime.latestSnapshot = snapshot
        runtime.lastSimulationTickDate = timestamp
        return snapshot
    }

    private func syncLiveWeatherWindNoiseBaselineIfNeeded(
        runtime: inout TransmitRuntime,
        fetchedAt: Date
    ) {
        if runtime.liveWeatherNoiseBaselineFetchDate != fetchedAt {
            runtime.liveWeatherNoiseBaselineFetchDate = fetchedAt
            runtime.liveWeatherWindSpeedOffsetKt = 0
            runtime.liveWeatherWindDirectionOffsetDeg = 0
        }
    }

    private func evolveLiveWeatherWindNoise(runtime: inout TransmitRuntime, deltaTime: TimeInterval) {
        let dt = min(max(deltaTime, 0), 4)
        guard dt > 0 else { return }

        let zSpeed = unitGaussianRandom()
        let zDir = unitGaussianRandom()

        let thetaSpeed = 0.07
        let sigmaSpeedKt = 0.017
        runtime.liveWeatherWindSpeedOffsetKt += -thetaSpeed * runtime.liveWeatherWindSpeedOffsetKt * dt + sigmaSpeedKt * sqrt(dt) * zSpeed
        runtime.liveWeatherWindSpeedOffsetKt = runtime.liveWeatherWindSpeedOffsetKt.clamped(to: -1.1...1.1)

        let thetaDir = 0.06
        let sigmaDirDeg = 0.22
        runtime.liveWeatherWindDirectionOffsetDeg += -thetaDir * runtime.liveWeatherWindDirectionOffsetDeg * dt + sigmaDirDeg * sqrt(dt) * zDir
        runtime.liveWeatherWindDirectionOffsetDeg = runtime.liveWeatherWindDirectionOffsetDeg.clamped(to: -10...10)
    }

    private func resolvedSteeringTrueHeading(
        runtime: TransmitRuntime,
        context: LiveCycleContext,
        variation: Double
    ) -> Double {
        if context.sensorToggles.hasGyro {
            return normalizeAngle(runtime.gyroHeading.value ?? runtime.gyroHeading.centerValue)
        }

        if context.sensorToggles.hasCompass {
            return normalizeAngle((runtime.heading.value ?? runtime.heading.centerValue) + variation)
        }

        return normalizeAngle(runtime.gpsData.courseOverGround)
    }

    private func computedTurnRate(
        currentHeading: Double,
        deltaTime: TimeInterval,
        previousReference: inout Double?
    ) -> Double {
        defer {
            previousReference = currentHeading
        }

        guard deltaTime > 0, let previousTurnReferenceHeading = previousReference else {
            return 0
        }

        let delta = calculateShortestRotation(from: previousTurnReferenceHeading, to: currentHeading)
        return delta / deltaTime * 60
    }

    private func estimatedBoatSpeed(
        trueHeading: Double,
        runtime: TransmitRuntime,
        context: LiveCycleContext
    ) -> Double? {
        guard context.sensorToggles.hasSpeedLog, let trueWindSpeed = runtime.tws.value else {
            return nil
        }

        let trueWindDirection = runtime.twd.value ?? runtime.gpsData.courseOverGround
        let trueWindAngle = abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))
        let baseSpeed = context.boatProfile.estimatedBoatSpeed(
            trueWindSpeedKnots: trueWindSpeed,
            trueWindAngleDegrees: trueWindAngle
        )

        let seaStatePenalty = context.weatherSourceMode == .liveWeather ? 0.96 : 1.0
        let variationPenalty = max(0.88, 1.0 - (runtime.speed.offset / 100))
        return (baseSpeed * seaStatePenalty * variationPenalty).clamped(to: SimulatedValueType.speedLog.defaultRange)
    }

    private func applyFaultInjection(
        to sentences: [String],
        for type: NMEASentenceType,
        at timestamp: Date,
        context: LiveCycleContext,
        runtime: inout TransmitRuntime
    ) -> [String] {
        guard context.faultInjection.isEnabled else {
            return sentences
        }

        var transmitted: [String] = []

        for sentence in sentences {
            if shouldInjectFault(rate: context.faultInjection.dropRate) {
                appendHistoryEventOnMain(
                    level: .warning,
                    category: .fault,
                    message: "Dropped \(type.rawValue.uppercased()) sentence"
                )
                continue
            }

            var mutated = sentence

            if shouldInjectFault(rate: context.faultInjection.invalidDataRate),
               let invalidSentence = invalidatedSentence(from: mutated, type: type) {
                mutated = invalidSentence
                appendHistoryEventOnMain(
                    level: .warning,
                    category: .fault,
                    message: "Injected invalid data into \(type.rawValue.uppercased()) sentence"
                )
            }

            if shouldInjectFault(rate: context.faultInjection.checksumCorruptionRate),
               let corrupted = corruptedChecksumSentence(from: mutated) {
                mutated = corrupted
                appendHistoryEventOnMain(
                    level: .warning,
                    category: .fault,
                    message: "Corrupted checksum for \(type.rawValue.uppercased()) sentence"
                )
            }

            if shouldInjectFault(rate: context.faultInjection.delayRate) {
                let delayCycles = max(1, Int.random(in: 1...max(1, context.faultInjection.maximumDelayCycles)))
                let dueDate = timestamp.addingTimeInterval(context.interval * Double(delayCycles))
                runtime.pendingTransmissions.append(PendingTransmission(sentence: mutated, dueDate: dueDate))
                appendHistoryEventOnMain(
                    level: .warning,
                    category: .fault,
                    message: "Delayed \(type.rawValue.uppercased()) sentence by \(delayCycles) cycle(s)"
                )
                continue
            }

            transmitted.append(mutated)
        }

        return transmitted
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
