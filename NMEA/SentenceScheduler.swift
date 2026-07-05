import Foundation

/// Pure scheduling and fault-injection logic for NMEA sentence emission.
///
/// All methods are static and side-effect-free. Callers are responsible for
/// network sends, console recording, and history event logging.
enum SentenceScheduler {

    // MARK: - Result types

    /// A fault-injection event that the caller should log to transport history.
    struct FaultEvent {
        let level: TransportStatusLevel
        let message: String
    }

    /// A sentence queued for delayed transmission (stagger or fault delay).
    struct DelayedSentence {
        let sentence: String
        let dueDate: Date
    }

    /// The output of fault injection for a single sentence type.
    struct FaultInjectionResult {
        /// Sentences that survived fault injection and should be sent.
        var transmitted: [String] = []
        /// Sentences delayed by fault injection (cycle-based delay).
        var delayed: [DelayedSentence] = []
        /// Events to log to transport history.
        var events: [FaultEvent] = []
    }

    /// The output of a single scheduling cycle.
    struct ScheduleResult {
        /// Sentences to send immediately (no stagger delay).
        var immediateSentences: [(sentence: String, type: NMEASentenceType)] = []
        /// Sentences queued for staggered or fault-delayed transmission.
        var delayedSentences: [DelayedSentence] = []
        /// Fault events to log to transport history.
        var faultEvents: [FaultEvent] = []
    }

    // MARK: - Stagger + build + fault-inject pipeline

    /// Computes the full scheduling output for one simulation cycle.
    ///
    /// This method unifies the stagger + build + fault-inject pipeline that was
    /// previously duplicated between the main-thread and off-main code paths.
    ///
    /// - Parameters:
    ///   - dueSentences: The sentence types due for emission this cycle.
    ///   - snapshot: The current simulation snapshot.
    ///   - config: The current simulation config.
    ///   - interval: The global timer interval (used for stagger window and fault delay).
    ///   - timestamp: The current cycle timestamp.
    ///   - sentenceBuilder: Builds raw NMEA sentences for a given (talkerID, type, snapshot).
    ///   - talkerIDResolver: Returns the effective talker ID for a sentence type.
    /// - Returns: A `ScheduleResult` with immediate sentences, delayed sentences, and fault events.
    static func scheduleSentences(
        dueSentences: [NMEASentenceType],
        snapshot: SimulationSnapshot,
        config: SimulationConfig,
        interval: TimeInterval,
        at timestamp: Date,
        sentenceBuilder: (String, NMEASentenceType, SimulationSnapshot) -> [String],
        talkerIDResolver: (NMEASentenceType) -> String
    ) -> ScheduleResult {
        let count = dueSentences.count
        guard count > 0 else { return ScheduleResult() }

        let staggerWindow = min(interval * 0.8, Double(count - 1) * 0.05)
        let gap = count > 1 ? staggerWindow / Double(count - 1) : 0

        var result = ScheduleResult()

        for (index, type) in dueSentences.enumerated() {
            let delay = gap * Double(index)
            let talkerID = talkerIDResolver(type)
            let rawSentences = sentenceBuilder(talkerID, type, snapshot)

            let faultResult = applyFaultInjection(
                to: rawSentences,
                for: type,
                at: snapshot.timestamp,
                faultInjection: config.faultInjection,
                interval: interval
            )
            result.faultEvents.append(contentsOf: faultResult.events)
            result.delayedSentences.append(contentsOf: faultResult.delayed)

            if delay < 0.001 {
                // Send immediately.
                for sentence in faultResult.transmitted {
                    result.immediateSentences.append((sentence: sentence, type: type))
                }
            } else {
                // Stagger-delayed.
                let dueDate = timestamp.addingTimeInterval(delay)
                for sentence in faultResult.transmitted {
                    result.delayedSentences.append(DelayedSentence(sentence: sentence, dueDate: dueDate))
                }
            }
        }

        return result
    }

    /// The stagger flush timestamp for sentences queued in the current cycle.
    ///
    /// After calling `scheduleSentences`, the caller should flush pending transmissions
    /// at this timestamp to deliver staggered sentences on time.
    static func staggerFlushTimestamp(
        sentenceCount: Int,
        interval: TimeInterval,
        cycleTimestamp: Date
    ) -> Date? {
        guard sentenceCount > 1 else { return nil }
        let staggerWindow = min(interval * 0.8, Double(sentenceCount - 1) * 0.05)
        return cycleTimestamp.addingTimeInterval(staggerWindow + 0.001)
    }

    // MARK: - Fault injection (pure)

    /// Applies fault injection to raw sentences for a single sentence type.
    ///
    /// Returns surviving sentences, fault-delayed sentences, and loggable events.
    static func applyFaultInjection(
        to sentences: [String],
        for type: NMEASentenceType,
        at timestamp: Date,
        faultInjection: FaultInjectionSettings,
        interval: TimeInterval
    ) -> FaultInjectionResult {
        guard faultInjection.isEnabled else {
            return FaultInjectionResult(transmitted: sentences)
        }

        var result = FaultInjectionResult()

        for sentence in sentences {
            if shouldInjectFault(rate: faultInjection.dropRate) {
                result.events.append(FaultEvent(
                    level: .warning,
                    message: "Dropped \(type.rawValue.uppercased()) sentence"
                ))
                continue
            }

            var mutated = sentence

            if shouldInjectFault(rate: faultInjection.invalidDataRate),
               let invalidSentence = invalidatedSentence(from: mutated, type: type) {
                mutated = invalidSentence
                result.events.append(FaultEvent(
                    level: .warning,
                    message: "Injected invalid data into \(type.rawValue.uppercased()) sentence"
                ))
            }

            if shouldInjectFault(rate: faultInjection.checksumCorruptionRate),
               let corrupted = corruptedChecksumSentence(from: mutated) {
                mutated = corrupted
                result.events.append(FaultEvent(
                    level: .warning,
                    message: "Corrupted checksum for \(type.rawValue.uppercased()) sentence"
                ))
            }

            if shouldInjectFault(rate: faultInjection.delayRate) {
                let delayCycles = max(1, Int.random(in: 1...max(1, faultInjection.maximumDelayCycles)))
                let dueDate = timestamp.addingTimeInterval(interval * Double(delayCycles))
                result.delayed.append(DelayedSentence(sentence: mutated, dueDate: dueDate))
                result.events.append(FaultEvent(
                    level: .warning,
                    message: "Delayed \(type.rawValue.uppercased()) sentence by \(delayCycles) cycle(s)"
                ))
                continue
            }

            result.transmitted.append(mutated)
        }

        return result
    }

    // MARK: - Fault helpers (pure)

    private static func shouldInjectFault(rate: Double) -> Bool {
        guard rate > 0 else { return false }
        return Double.random(in: 0...1) < min(max(rate, 0), 1)
    }

    static func invalidatedSentence(
        from sentence: String,
        type: NMEASentenceType
    ) -> String? {
        guard let payload = payload(from: sentence) else { return nil }

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

    static func corruptedChecksumSentence(from sentence: String) -> String? {
        guard let starIndex = sentence.firstIndex(of: "*") else { return nil }
        let prefix = sentence[..<sentence.index(after: starIndex)]
        return "\(prefix)00\r\n"
    }

    private static func payload(from sentence: String) -> String? {
        guard sentence.first == "$", let starIndex = sentence.firstIndex(of: "*") else {
            return nil
        }
        let startIndex = sentence.index(after: sentence.startIndex)
        return String(sentence[startIndex..<starIndex])
    }

    /// Computes an NMEA checksum and appends it to the sentence.
    static func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }
}
