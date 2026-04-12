import Foundation
import Network
import Observation
import CoreLocation

@Observable
class NMEASimulator {
    private struct PendingTransmission {
        let sentence: String
        let dueDate: Date
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
            syncPrimaryOutputEndpoint()
            persistSettingsIfNeeded()
        }
    }
    var port: UInt16 = 4950 {
        didSet {
            syncPrimaryOutputEndpoint()
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
            normalizeOutputEndpoints()
            persistSettingsIfNeeded()
        }
    }

    private let udpClient = UDPClient()
    private let tcpClient = TCPClient()
    private var timer: Timer?

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
            if isTransmitting && isTimerSelected {
                restartTimer()
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
    var weatherSourceMode: WeatherSourceMode = .manual {
        didSet {
            guard !isRestoringSettings else { return }

            if weatherSourceMode == .manual {
                liveWeatherTask?.cancel()
                liveWeatherTask = nil
                liveWeatherStatus = .idle
            } else {
                selectedPreset = nil
                latestLiveWeather = nil
                twd.value = nil
                tws.value = nil
                seaTemp.value = nil
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

    // MARK: - Dashboard Indicator

    var isTransmitting: Bool = false
    private(set) var endpointStatuses: [UUID: OutputEndpointStatus] = [:]
    private(set) var latestTransportStatus: OutputEndpointStatus?
    private(set) var transportHistory: [TransportHistoryEvent] = []

    // MARK: - Console

    var outputMessages: [String] = []
    private(set) var outputMessageTimestamps: [Date] = []

    // MARK: - Engine State

    private(set) var latestSnapshot: SimulationSnapshot?

    private var lastSimulationTickDate: Date?
    private var lastEmissionDates: [NMEASentenceType: Date] = [:]
    private var sentenceIntervals: [NMEASentenceType: TimeInterval] = Dictionary(
        uniqueKeysWithValues: NMEASentenceType.allCases.map { ($0, 0) }
    ) {
        didSet { persistSettingsIfNeeded() }
    }
    private var sendRelativeWind = true
    private var previousTurnReferenceHeading: Double?
    private var totalLogDistanceNm: Double = 0
    private var totalTripDistanceNm: Double = 0
    private var isRestoringSettings = false
    private var isSynchronizingEndpoints = false
    private var pendingTransmissions: [PendingTransmission] = []
    @ObservationIgnored private var liveWeatherTask: Task<Bool, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        weatherService: any WeatherService = GlobalFallbackWeatherService()
    ) {
        self.userDefaults = userDefaults
        self.weatherService = weatherService
        tcpClient.onStateChange = { [weak self] endpoint, state in
            self?.handleTCPStateUpdate(state, for: endpoint)
        }
        loadPersistedSettings()
        normalizeOutputEndpoints()
        if weatherSourceMode == .liveWeather {
            refreshLiveWeather(force: true)
        }
    }

    func persistLiveSettings() {
        persistSettingsIfNeeded()
    }

    func clearOutputMessages() {
        outputMessages.removeAll()
        outputMessageTimestamps.removeAll()
    }

    func outputMessageTimestamp(at index: Int) -> Date? {
        let offset = outputMessageTimestamps.count - outputMessages.count
        let adjustedIndex = index + offset
        guard adjustedIndex >= 0, adjustedIndex < outputMessageTimestamps.count else {
            return nil
        }
        return outputMessageTimestamps[adjustedIndex]
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
        runSimulationCycle()
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

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runSimulationCycle()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        isTransmitting = true
        appendHistoryEvent(level: .connected, category: .lifecycle, message: "Simulation started")
        runSimulationCycle()
    }

    func stopSimulation() {
        let wasRunning = isTransmitting || timer != nil
        isTransmitting = false
        if !wasRunning {
            liveWeatherTask?.cancel()
            liveWeatherTask = nil
        }
        timer?.invalidate()
        timer = nil
        udpClient.resetConnections()
        tcpClient.resetConnections()
        var latestIdleStatus: OutputEndpointStatus?

        for endpoint in outputEndpoints {
            let idleStatus = OutputEndpointStatus(
                endpointID: endpoint.id,
                level: .idle,
                message: "\(endpoint.transport.rawValue.uppercased()) \(endpoint.host):\(endpoint.port) idle"
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
        sentenceIntervals[sentence] = max(0, interval)
    }

    func sentenceInterval(for sentence: NMEASentenceType) -> Double {
        sentenceIntervals[sentence] ?? 0
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
            latestLiveWeather = snapshot
            applyResolvedLiveWeatherValues()
            liveWeatherStatus = LiveWeatherStatus(
                state: .ready,
                message: "Live weather updated from \(snapshot.sourceName).",
                lastUpdated: snapshot.fetchedAt
            )
            return true
        } catch {
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
        flushPendingTransmissions(at: timestamp)
        let snapshot = tickSimulation(at: timestamp)
        let dueSentences = scheduledSentenceTypes(at: timestamp, snapshot: snapshot)

        for type in dueSentences {
            sendNMEA(talkerID: talkerID, type: type, snapshot: snapshot)
        }
    }

    private func tickSimulation(at timestamp: Date) -> SimulationSnapshot {
        let deltaTime = max(0, resolvedDeltaTime(for: timestamp))
        triggerLiveWeatherRefreshIfNeeded(at: timestamp)

        if weatherSourceMode == .liveWeather {
            if let liveWeather = activeLiveWeather {
                twd.value = sensorToggles.hasAnemometer
                    ? generateLiveWeatherValue(
                        base: liveWeather.trueWindDirection,
                        jitter: 6,
                        range: SimulatedValueType.windDirection.defaultRange,
                        wraps: true
                    )
                    : nil
                tws.value = sensorToggles.hasAnemometer
                    ? generateLiveWeatherValue(
                        base: liveWeather.trueWindSpeedKnots,
                        jitter: 0.9,
                        range: SimulatedValueType.windSpeed.defaultRange,
                        wraps: false
                    )
                    : nil
                seaTemp.value = sensorToggles.hasWaterTempSensor
                    ? generateLiveWeatherValue(
                        base: liveWeather.seaSurfaceTemperatureCelsius,
                        jitter: 0.3,
                        range: SimulatedValueType.seaTemp.defaultRange,
                        wraps: false
                    )
                    : nil
            } else {
                twd.value = nil
                tws.value = nil
                seaTemp.value = nil
            }
        } else {
            twd.value = twd.generateRandomValue(shouldGenerate: sensorToggles.hasAnemometer)
            tws.value = tws.generateRandomValue(shouldGenerate: sensorToggles.hasAnemometer)
            seaTemp.value = seaTemp.generateRandomValue(shouldGenerate: sensorToggles.hasWaterTempSensor)
        }

        heading.value = heading.generateRandomValue(shouldGenerate: sensorToggles.hasCompass)
        gyroHeading.value = gyroHeading.generateRandomValue(shouldGenerate: sensorToggles.hasGyro)
        depth.value = depth.generateRandomValue(shouldGenerate: sensorToggles.hasEchoSounder)
        speed.value = speed.generateRandomValue(shouldGenerate: sensorToggles.hasSpeedLog)

        let magneticVariation = simulatedMagneticVariation(for: gpsData, at: timestamp)
        let boatTrueHeading = resolvedTrueHeading(magneticHeading: heading.value, gyroHeading: gyroHeading.value, variation: magneticVariation) ?? gpsData.courseOverGround
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
            gpsData: gpsData,
            gpsSignal: gpsSignal,
            turnRate: turnRate,
            logDistanceNm: totalLogDistanceNm,
            tripDistanceNm: totalTripDistanceNm
        )

        latestSnapshot = snapshot
        lastSimulationTickDate = timestamp
        return snapshot
    }

    private func sendNMEA(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) {
        let sentences = applyFaultInjection(
            to: buildNMEASentences(talkerID: talkerID, type: type, snapshot: snapshot),
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
            let minimumInterval = sentenceIntervals[type] ?? 0
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
        }

        return types
    }

    private func enabledOutputEndpoints() -> [OutputEndpoint] {
        syncPrimaryOutputEndpoint()
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
                        message: "\(endpoint.transport.rawValue.uppercased()) connected to \(endpoint.host):\(endpoint.port)"
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
                        message: "\(endpoint.transport.rawValue.uppercased()) \(endpoint.host):\(endpoint.port) - \(self.transportErrorSummary(error))"
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
                        message: "TCP connecting to \(endpoint.host):\(endpoint.port)"
                    )
                )
            case .ready:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .connected,
                        message: "TCP connected to \(endpoint.host):\(endpoint.port)"
                    )
                )
            case .waiting:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .warning,
                        message: "TCP waiting for \(endpoint.host):\(endpoint.port)"
                    )
                )
            case .failed(let error, let retryAfter):
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .error,
                        message: "TCP \(endpoint.host):\(endpoint.port) - \(self.transportErrorSummary(error)) (retry after \(retryAfter.formatted(date: .omitted, time: .standard)))"
                    )
                )
            case .cancelled:
                self.recordTransportStatus(
                    OutputEndpointStatus(
                        endpointID: endpoint.id,
                        level: .idle,
                        message: "TCP \(endpoint.host):\(endpoint.port) idle"
                    )
                )
            }
        }
    }

    private func recordTransportStatus(_ status: OutputEndpointStatus) {
        let previousStatus = endpointStatuses[status.endpointID]
        endpointStatuses[status.endpointID] = status

        if latestTransportStatus == nil || status.level == .error || status.level == .warning || latestTransportStatus?.level == .connected {
            latestTransportStatus = status
        }

        let statusChanged = previousStatus?.level != status.level || previousStatus?.message != status.message
        if statusChanged {
            appendHistoryEvent(
                endpointID: status.endpointID,
                level: status.level,
                category: .transport,
                message: status.message,
                timestamp: status.updatedAt
            )
        }
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

        if ip != outputEndpoints[0].host {
            ip = outputEndpoints[0].host
        }

        if port != outputEndpoints[0].port {
            port = outputEndpoints[0].port
        }
    }

    private func persistSettingsIfNeeded() {
        guard !isRestoringSettings else {
            return
        }

        persistSettings()
    }

    private func persistSettings() {
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
            heading: heading,
            gyroHeading: gyroHeading,
            gpsData: gpsData,
            faultInjection: faultInjection,
            mwvReferenceMode: mwvReferenceMode,
            selectedPreset: selectedPreset,
            weatherSourceMode: weatherSourceMode,
            liveWeatherSettings: liveWeatherSettings,
            latestLiveWeather: latestLiveWeather
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
                (type, settings.sentenceIntervals[type.rawValue] ?? 0)
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
        heading = settings.heading
        gyroHeading = settings.gyroHeading
        gpsData = settings.gpsData
        faultInjection = settings.faultInjection
        mwvReferenceMode = settings.mwvReferenceMode
        selectedPreset = settings.selectedPreset
        weatherSourceMode = settings.weatherSourceMode
        liveWeatherSettings = settings.liveWeatherSettings
        latestLiveWeather = settings.latestLiveWeather
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
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runSimulationCycle()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func handleTimerSelectionChange() {
        guard !isRestoringSettings else {
            return
        }

        if isTimerSelected {
            if isTransmitting && timer == nil {
                restartTimer()
                appendHistoryEvent(level: .connected, category: .lifecycle, message: "Timer re-enabled")
            }
            return
        }

        if timer != nil {
            timer?.invalidate()
            timer = nil
            isTransmitting = false
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
        outputMessages.append(sentence)
        outputMessageTimestamps.append(timestamp)

        if outputMessages.count > 100 {
            outputMessages.removeFirst(outputMessages.count - 100)
        }

        if outputMessageTimestamps.count > 100 {
            outputMessageTimestamps.removeFirst(outputMessageTimestamps.count - 100)
        }
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
}

// MARK: - Interlock Helpers

extension NMEASimulator {

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
