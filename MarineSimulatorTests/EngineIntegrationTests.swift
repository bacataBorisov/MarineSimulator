import Darwin
import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct EngineIntegrationTests {
    // MARK: - UDP loopback

    @Test @MainActor
    func udpLoopbackReceivesValidNMEASentence() throws {
        let listener = try UDPLoopbackListener.bind()
        defer { listener.close() }

        let simulator = configuredSimulatorForTransport(host: "127.0.0.1", port: listener.port)
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendRMC)
        simulator.interval = 0.5
        simulator.isTimerSelected = true

        let receiveBox = AsyncResultBox<String>()
        DispatchQueue.global(qos: .userInitiated).async {
            receiveBox.complete(with: Result { try listener.receiveFirstSentence(timeout: 3.0) })
        }

        defer { simulator.stopSimulation() }
        simulator.startSimulation()

        let sentence = try waitForAsyncResult(receiveBox, timeout: 3.5)
        #expect(isValidNMEASentence(sentence))
        #expect(sentence.contains("RMC"))
    }

    // MARK: - TCP loopback

    @Test @MainActor
    func tcpListenerAcceptsConnectionAndReceivesNMEASentences() throws {
        let listener = try TCPTestListener.bind()
        defer { listener.close() }

        let receiveBox = AsyncResultBox<TCPReceiveResult>()
        DispatchQueue.global(qos: .userInitiated).async {
            receiveBox.complete(with: Result { try listener.acceptAndReceiveFirstSentence(timeout: 5.0) })
        }

        let simulator = configuredSimulatorForTransport(host: "127.0.0.1", port: listener.port)
        simulator.outputEndpoints[0].transport = .tcp
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendRMC)
        simulator.interval = 0.5
        simulator.isTimerSelected = true

        defer { simulator.stopSimulation() }
        simulator.startSimulation()

        let result = try waitForAsyncResult(receiveBox, timeout: 6.0)
        #expect(result.connectionAccepted)
        #expect(isValidNMEASentence(result.sentence))
        #expect(result.sentence.contains("RMC"))
    }

    // MARK: - Timer-driven fast rate (P0 regression)

    @Test @MainActor
    func timerDrivenRealisticProfileEmitsHDTNear10Hz() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendHDT)
        simulator.clearOutputMessages()
        simulator.isTimerSelected = true

        defer { simulator.stopSimulation() }
        simulator.startSimulation()
        pumpMainRunLoop(for: 1.5)

        let hdtCount = countSentences(
            in: simulator,
            matching: { $0.contains("HDT") },
            duringLast: 1.2
        )
        #expect(hdtCount >= 6)
        #expect(hdtCount <= 16)
    }

    // MARK: - Simulation tick persistence debounce

    @Test @MainActor
    func simulationTicksDoNotPersistOnEveryTick() {
        let defaults = isolatedDefaults()
        let simulator = configuredSimulatorForDeterministicOutput(userDefaults: defaults)
        simulator.outputEndpoints[0].isEnabled = false
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.interval = 0.1

        simulator.sendAllSelectedNMEA()
        let persistCountAtStart = simulator.persistSettingsInvocationCount

        for _ in 0..<25 {
            simulator.sendAllSelectedNMEA()
            Thread.sleep(forTimeInterval: 0.11)
        }

        #expect(simulator.persistSettingsInvocationCount == persistCountAtStart)
    }

    // MARK: - Tack heading coherence at transmit boundaries

    @Test @MainActor
    func tackTransmitHeadingMatchesDashboardHeading() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.applyHardwareProfile(.bngTriton2)
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendHDT)
        simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0, value: 90)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 45, offset: 0, value: 45)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 45, offset: 0, value: 45)
        simulator.clearOutputMessages()
        simulator.isTimerSelected = true

        defer { simulator.stopSimulation() }
        simulator.startSimulation()
        simulator.beginTackManeuver()

        var checkedMessages = 0
        var hdtCount = 0
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            Thread.sleep(forTimeInterval: 0.03)

            while checkedMessages < simulator.allOutputMessageRecords.count {
                let message = simulator.allOutputMessageRecords[checkedMessages].sentence
                checkedMessages += 1

                guard message.contains("HDT"), let transmitted = parseTrueHeading(fromHDT: message) else {
                    continue
                }

                hdtCount += 1
                let dashboardHeading = simulator.geographicBearingDegreesForMap
                let delta = abs(calculateShortestRotation(from: transmitted, to: dashboardHeading))
                #expect(delta <= 0.2, "HDT \(transmitted) vs dashboard \(dashboardHeading)")
            }
        }

        #expect(hdtCount >= 3)
    }
}

// MARK: - Async coordination

private final class AsyncResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<T, Error>?

    func complete(with result: Result<T, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }

    func poll() -> Result<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

@MainActor
private func waitForAsyncResult<T>(_ box: AsyncResultBox<T>, timeout: TimeInterval) throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if let result = box.poll() {
            return try result.get()
        }
    }
    throw IntegrationTestError.receiveTimedOut
}

@MainActor
private func pumpMainRunLoop(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        Thread.sleep(forTimeInterval: 0.03)
    }
}

// MARK: - Transport fixtures

private struct TCPReceiveResult: Sendable {
    let connectionAccepted: Bool
    let sentence: String
}

private final class UDPLoopbackListener: @unchecked Sendable {
    let fd: Int32
    let port: UInt16

    private init(fd: Int32, port: UInt16) {
        self.fd = fd
        self.port = port
    }

    static func bind(host: String = "127.0.0.1") throws -> UDPLoopbackListener {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw IntegrationTestError.socketCreationFailed
        }

        var reuse: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = Darwin.inet_addr(host)

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                Darwin.bind(fd, sockaddr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw IntegrationTestError.bindFailed
        }

        var bound = addr
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &bound, { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                Darwin.getsockname(fd, sockaddr, &boundLen)
            }
        }) == 0 else {
            Darwin.close(fd)
            throw IntegrationTestError.bindFailed
        }

        return UDPLoopbackListener(fd: fd, port: UInt16(bigEndian: bound.sin_port))
    }

    func receiveFirstSentence(timeout: TimeInterval) throws -> String {
        var timeoutVal = timeval(
            tv_sec: __darwin_time_t(timeout),
            tv_usec: __darwin_suseconds_t((timeout - floor(timeout)) * 1_000_000)
        )
        _ = Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeoutVal,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var buffer = [UInt8](repeating: 0, count: 4096)
        var source = sockaddr_in()
        var sourceLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let received = buffer.withUnsafeMutableBytes { rawBuffer in
            withUnsafeMutablePointer(to: &source) { sourcePointer in
                sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                    Darwin.recvfrom(
                        fd,
                        rawBuffer.baseAddress,
                        rawBuffer.count,
                        0,
                        sockaddr,
                        &sourceLen
                    )
                }
            }
        }

        guard received > 0 else {
            throw IntegrationTestError.receiveTimedOut
        }

        guard let sentence = String(bytes: buffer.prefix(received), encoding: .utf8) else {
            throw IntegrationTestError.invalidPayload
        }
        return sentence
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
        }
    }
}

private final class TCPTestListener: @unchecked Sendable {
    let listenFD: Int32
    let port: UInt16

    private init(listenFD: Int32, port: UInt16) {
        self.listenFD = listenFD
        self.port = port
    }

    static func bind(host: String = "127.0.0.1") throws -> TCPTestListener {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IntegrationTestError.socketCreationFailed
        }

        var reuse: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = Darwin.inet_addr(host)

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                Darwin.bind(fd, sockaddr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw IntegrationTestError.bindFailed
        }

        guard Darwin.listen(fd, 1) == 0 else {
            Darwin.close(fd)
            throw IntegrationTestError.bindFailed
        }

        var bound = addr
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &bound, { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                Darwin.getsockname(fd, sockaddr, &boundLen)
            }
        }) == 0 else {
            Darwin.close(fd)
            throw IntegrationTestError.bindFailed
        }

        return TCPTestListener(listenFD: fd, port: UInt16(bigEndian: bound.sin_port))
    }

    func acceptAndReceiveFirstSentence(timeout: TimeInterval) throws -> TCPReceiveResult {
        var timeoutVal = timeval(
            tv_sec: __darwin_time_t(timeout),
            tv_usec: __darwin_suseconds_t((timeout - floor(timeout)) * 1_000_000)
        )
        _ = Darwin.setsockopt(
            listenFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeoutVal,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var clientAddr = sockaddr_in()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                Darwin.accept(listenFD, sockaddr, &clientAddrLen)
            }
        }
        guard clientFD >= 0 else {
            throw IntegrationTestError.receiveTimedOut
        }
        defer { Darwin.close(clientFD) }

        _ = Darwin.setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeoutVal,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.recv(clientFD, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        guard received > 0 else {
            throw IntegrationTestError.receiveTimedOut
        }

        guard let sentence = String(bytes: buffer.prefix(received), encoding: .utf8) else {
            throw IntegrationTestError.invalidPayload
        }

        return TCPReceiveResult(connectionAccepted: true, sentence: sentence)
    }

    func close() {
        if listenFD >= 0 {
            Darwin.close(listenFD)
        }
    }
}

private enum IntegrationTestError: Error {
    case socketCreationFailed
    case bindFailed
    case receiveTimedOut
    case invalidPayload
}

// MARK: - Shared helpers

private func countSentences(
    in simulator: NMEASimulator,
    matching predicate: (String) -> Bool,
    duringLast seconds: TimeInterval
) -> Int {
    let cutoff = Date().addingTimeInterval(-seconds)
    var count = 0
    for record in simulator.allOutputMessageRecords {
        guard predicate(record.sentence) else { continue }
        guard record.timestamp >= cutoff else { continue }
        count += 1
    }
    return count
}

private func parseTrueHeading(fromHDT sentence: String) -> Double? {
    guard sentence.contains("HDT") else { return nil }
    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = trimmed.hasPrefix("$") ? String(trimmed.dropFirst()) : trimmed
    let fields = body.split(separator: "*", maxSplits: 1).first?.split(separator: ",") ?? []
    guard fields.count >= 2, let heading = Double(fields[1]) else { return nil }
    return heading
}

@MainActor
private func configuredSimulatorForTransport(host: String, port: UInt16) -> NMEASimulator {
    let simulator = configuredSimulatorForDeterministicOutput()
    simulator.ip = host
    simulator.port = port
    simulator.outputEndpoints[0].host = host
    simulator.outputEndpoints[0].port = port
    simulator.outputEndpoints[0].transport = .udp
    simulator.outputEndpoints[0].isEnabled = true
    return simulator
}

private func configuredSimulatorForDeterministicOutput(userDefaults: UserDefaults? = nil) -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: userDefaults ?? isolatedDefaults())
    simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 10, offset: 0)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0)
    simulator.depth = SimulatedValue(type: .depth, center: 12, offset: 0)
    simulator.seaTemp = SimulatedValue(type: .seaTemp, center: 18, offset: 0)
    simulator.gpsData = GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90)
    simulator.mwvReferenceMode = .relative
    return simulator
}

private func onlyEnabledSentence(_ keyPath: WritableKeyPath<SentenceToggleStates, Bool>) -> SentenceToggleStates {
    var toggles = SentenceToggleStates(
        shouldSendMWV: false,
        shouldSendMWD: false,
        shouldSendVPW: false,
        shouldSendHDG: false,
        shouldSendHDT: false,
        shouldSendROT: false,
        shouldSendRMC: false,
        shouldSendGGA: false,
        shouldSendVTG: false,
        shouldSendGLL: false,
        shouldSendGSA: false,
        shouldSendGSV: false,
        shouldSendZDA: false,
        shouldSendDBT: false,
        shouldSendDPT: false,
        shouldSendVHW: false,
        shouldSendVLW: false,
        shouldSendVBW: false,
        shouldSendMTW: false,
        shouldSendRMB: false,
        shouldSendXTE: false
    )
    toggles[keyPath: keyPath] = true
    return toggles
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "MarineSimulatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "test-suite-name")
    return defaults
}

private func isValidNMEASentence(_ sentence: String) -> Bool {
    guard sentence.hasPrefix("$"),
          sentence.hasSuffix("\r\n"),
          let starIndex = sentence.firstIndex(of: "*")
    else {
        return false
    }

    let payload = sentence[sentence.index(after: sentence.startIndex)..<starIndex]
    let checksumStart = sentence.index(after: starIndex)
    let checksumEnd = sentence.index(checksumStart, offsetBy: 2, limitedBy: sentence.endIndex) ?? sentence.endIndex
    let providedChecksum = String(sentence[checksumStart..<checksumEnd])

    guard providedChecksum.count == 2 else {
        return false
    }

    let computedChecksum = payload.reduce(0) { partialResult, character in
        partialResult ^ Int(character.asciiValue ?? 0)
    }

    return providedChecksum.uppercased() == String(format: "%02X", computedChecksum)
}
