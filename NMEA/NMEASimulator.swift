import Foundation
import Observation

@Observable
class NMEASimulator {

    // MARK: - Sensors & Sentences States

    var sentenceToggles = SentenceToggleStates()
    var sensorToggles = SensorToggleStates()

    // MARK: - Network & Connectivity

    var ip: String = "127.0.0.1" {
        didSet { syncPrimaryOutputEndpoint() }
    }
    var port: UInt16 = 4950 {
        didSet { syncPrimaryOutputEndpoint() }
    }
    var talkerID: String = "II"
    var outputEndpoints: [OutputEndpoint] = [
        OutputEndpoint(host: "127.0.0.1", port: 4950)
    ]

    private let udpClient = UDPClient()
    private var timer: Timer?

    var isTimerSelected = true
    var interval: Double = 1.0 {
        didSet {
            if isTransmitting && isTimerSelected {
                restartTimer()
            }
        }
    }

    // MARK: - Wind

    var twd = SimulatedValue(type: .windDirection)
    var tws = SimulatedValue(type: .windSpeed)

    // MARK: - Hydro

    var speed = SimulatedValue(type: .speedLog)
    var depth = SimulatedValue(type: .depth)
    var depthOffsetMeters: Double = 0.0
    var seaTemp = SimulatedValue(type: .seaTemp)

    // MARK: - Compass

    var heading = SimulatedValue(type: .magneticCompass)
    var gyroHeading = SimulatedValue(type: .gyroCompass)

    // MARK: - GPS & Positioning

    var gpsData = GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90)

    // MARK: - Dashboard Indicator

    var isTransmitting: Bool = false

    // MARK: - Console

    var outputMessages: [String] = []

    // MARK: - Engine State

    private(set) var latestSnapshot: SimulationSnapshot?

    private var lastSimulationTickDate: Date?
    private var lastEmissionDates: [NMEASentenceType: Date] = [:]
    private var sentenceIntervals: [NMEASentenceType: TimeInterval] = Dictionary(
        uniqueKeysWithValues: NMEASentenceType.allCases.map { ($0, 0) }
    )
    private var sendRelativeWind = true
    private var previousTurnReferenceHeading: Double?
    private var totalLogDistanceNm: Double = 0
    private var totalTripDistanceNm: Double = 0

    func sendAllSelectedNMEA() {
        runSimulationCycle()
    }

    func startSimulation() {
        syncPrimaryOutputEndpoint()
        stopSimulation()
        resetEngineForNewRun()

        if isTimerSelected {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.runSimulationCycle()
            }
            if let timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        isTransmitting = true
        runSimulationCycle()
    }

    func stopSimulation() {
        isTransmitting = false
        timer?.invalidate()
        timer = nil
        udpClient.resetConnections()
    }

    func setInterval(_ interval: TimeInterval, for sentence: NMEASentenceType) {
        sentenceIntervals[sentence] = max(0, interval)
    }

    private func runSimulationCycle(at timestamp: Date = .now) {
        let snapshot = tickSimulation(at: timestamp)
        let dueSentences = scheduledSentenceTypes(at: timestamp, snapshot: snapshot)

        for type in dueSentences {
            sendNMEA(talkerID: talkerID, type: type, snapshot: snapshot)
        }
    }

    private func tickSimulation(at timestamp: Date) -> SimulationSnapshot {
        let deltaTime = max(0, resolvedDeltaTime(for: timestamp))

        twd.value = twd.generateRandomValue(shouldGenerate: sensorToggles.hasAnemometer)
        tws.value = tws.generateRandomValue(shouldGenerate: sensorToggles.hasAnemometer)

        heading.value = heading.generateRandomValue(shouldGenerate: sensorToggles.hasCompass)
        gyroHeading.value = gyroHeading.generateRandomValue(shouldGenerate: sensorToggles.hasGyro)

        seaTemp.value = seaTemp.generateRandomValue(shouldGenerate: sensorToggles.hasWaterTempSensor)
        depth.value = depth.generateRandomValue(shouldGenerate: sensorToggles.hasEchoSounder)
        speed.value = speed.generateRandomValue(shouldGenerate: sensorToggles.hasSpeedLog)

        let course = gyroHeading.value ?? heading.value ?? gpsData.courseOverGround
        let sog = speed.value ?? gpsData.speedOverGround

        if sensorToggles.hasGPS {
            gpsData.updatePosition(deltaTime: deltaTime, sog: sog, cog: course)
        }

        totalLogDistanceNm += max(0, speed.value ?? 0) * deltaTime / 3600
        totalTripDistanceNm += max(0, gpsData.speedOverGround) * deltaTime / 3600

        let turnRate = computedTurnRate(currentHeading: course, deltaTime: deltaTime)

        let snapshot = SimulationSnapshot(
            timestamp: timestamp,
            windDirectionTrue: twd.value,
            windSpeedTrue: tws.value,
            magneticHeading: heading.value,
            gyroHeading: gyroHeading.value,
            boatSpeed: speed.value,
            depth: depth.value,
            seaTemperature: seaTemp.value,
            gpsData: gpsData,
            turnRate: turnRate,
            logDistanceNm: totalLogDistanceNm,
            tripDistanceNm: totalTripDistanceNm
        )

        latestSnapshot = snapshot
        lastSimulationTickDate = timestamp
        return snapshot
    }

    private func sendNMEA(talkerID: String, type: NMEASentenceType, snapshot: SimulationSnapshot) {
        guard let sentence = buildNMEASentence(talkerID: talkerID, type: type, snapshot: snapshot) else {
            return
        }

        for endpoint in enabledOutputEndpoints() {
            udpClient.send(sentence, to: endpoint)
        }

        outputMessages.append(sentence)
        if outputMessages.count > 100 {
            outputMessages.removeFirst(outputMessages.count - 100)
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
        if sensorToggles.hasEchoSounder && sentenceToggles.shouldSendDPT {
            types.append(.dpt)
        }
        if sensorToggles.hasWaterTempSensor && sentenceToggles.shouldSendMTW {
            types.append(.mtw)
        }
        if (sensorToggles.hasSpeedLog || sensorToggles.hasCompass || sensorToggles.hasGyro) && sentenceToggles.shouldSendVHW {
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
        return outputEndpoints.filter { $0.isEnabled && $0.transport == .udp }
    }

    private func syncPrimaryOutputEndpoint() {
        let primary = OutputEndpoint(host: ip, port: port)
        if outputEndpoints.isEmpty {
            outputEndpoints = [primary]
            return
        }

        outputEndpoints[0].host = primary.host
        outputEndpoints[0].port = primary.port
        outputEndpoints[0].transport = primary.transport
        outputEndpoints[0].isEnabled = true
    }

    private func resetEngineForNewRun() {
        lastSimulationTickDate = nil
        lastEmissionDates.removeAll()
        previousTurnReferenceHeading = nil
        sendRelativeWind = true
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

    private func resolvedDeltaTime(for timestamp: Date) -> TimeInterval {
        if let lastSimulationTickDate {
            return timestamp.timeIntervalSince(lastSimulationTickDate)
        }
        return interval
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

    func nextMWVReference(in snapshot: SimulationSnapshot) -> String {
        let hasApparent = computeAWA(from: snapshot) != nil && computeAWS(from: snapshot) != nil
        let hasTrue = computeTWA(from: snapshot) != nil && computeTWS(from: snapshot) != nil

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
