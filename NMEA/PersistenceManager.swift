import Foundation

/// Encapsulates UserDefaults-based settings persistence.
/// Extracted from NMEASimulator (Phase 5 of the refactoring plan).
final class PersistenceManager {

    private enum Keys {
        static let simulatorSettings = "marine_simulator.settings"
    }

    private let userDefaults: UserDefaults
    private var debouncedWorkItem: DispatchWorkItem?

    private(set) var invocationCount = 0

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Persist

    /// Persists the current settings snapshot immediately, respecting guard flags.
    func persistIfNeeded(isRestoring: Bool, isApplyingTick: Bool, snapshot: () -> SimulatorSettings) {
        guard !isRestoring, !isApplyingTick else { return }
        persist(snapshot: snapshot())
    }

    /// Encodes and writes the settings snapshot to UserDefaults.
    func persist(snapshot: SimulatorSettings) {
        invocationCount += 1
        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: Keys.simulatorSettings)
        } catch {
            print("Failed to persist simulator settings: \(error)")
        }
    }

    /// Schedules a debounced persist after `delay` seconds, cancelling any pending one.
    func scheduleDebouncedPersist(delay: TimeInterval, snapshot: @escaping () -> SimulatorSettings?) {
        debouncedWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let settings = snapshot() else { return }
            self.persist(snapshot: settings)
        }
        debouncedWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancels any pending debounced persist.
    func cancelPendingPersist() {
        debouncedWorkItem?.cancel()
        debouncedWorkItem = nil
    }

    // MARK: - Load

    /// Loads and validates persisted settings from UserDefaults.
    /// Returns `nil` if no data is stored, or if validation/decoding fails (resets corrupt data).
    func loadSettings() -> SimulatorSettings? {
        // Use object(forKey:) first to verify the stored value is actually Data.
        // If a different type was stored under this key (e.g. a number from a
        // schema migration bug), calling data(forKey:) would trigger an ObjC
        // NSInvalidArgumentException that Swift's do/catch cannot intercept.
        guard let raw = userDefaults.object(forKey: Keys.simulatorSettings) else {
            return nil
        }
        guard let data = raw as? Data else {
            print("Persisted settings is not Data (found \(type(of: raw))) — resetting to defaults.")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }

        // Validate that the stored data is a JSON object before attempting decode.
        // Corrupted or schema-incompatible data can cause NSInvalidArgumentException
        // (ObjC exception) inside JSONDecoder which Swift's do/catch cannot intercept.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Persisted settings is not a valid JSON dictionary — resetting to defaults.")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }

        // Deep-validate the entire JSON tree. Any value that is a String/Number
        // where a Dictionary is expected will cause JSONDecoder to send
        // objectForKey: to an NSTaggedPointerString — an ObjC exception that
        // Swift cannot catch. Walk every nested dict/array recursively.
        if !Self.validateJSONStructure(json) {
            print("Persisted settings has corrupt nested structure — resetting to defaults.")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }

        // Re-serialize from the validated JSON object to produce clean Data.
        // This avoids any stale/corrupt Foundation bridge objects that may have
        // been deserialized from the original plist bytes.
        guard let cleanData = try? JSONSerialization.data(withJSONObject: json) else {
            print("Persisted settings failed re-serialization — resetting to defaults.")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }

        do {
            return try JSONDecoder().decode(SimulatorSettings.self, from: cleanData)
        } catch {
            print("Failed to restore simulator settings: \(error)")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }
    }

    // MARK: - Deep JSON Validation

    /// Recursively validates that the JSON structure is internally consistent:
    /// every dictionary value and array element is a valid JSON type, and no
    /// scalar appears where a container (dict/array) is expected by Codable.
    private static func validateJSONStructure(_ json: [String: Any]) -> Bool {
        // Keys that MUST be dictionaries when present (at any nesting level).
        // Only includes keys whose Codable type encodes as a JSON object.
        // Note: `boatProfile` is a String-backed enum (encodes as string).
        // Note: `range` (ClosedRange<Double>) encodes as an array [lb, ub].
        let requiredDictKeys: Set<String> = [
            "sentenceToggles", "sensorToggles", "twd", "tws",
            "speed", "depth", "heading", "gyroHeading", "gpsData",
            "faultInjection", "sentenceIntervals", "perSentenceTalkerID",
            "liveWeatherSettings", "latestLiveWeather", "waypointNavigation"
        ]

        for (key, value) in json {
            // outputEndpoints is an array of dicts.
            if key == "outputEndpoints" {
                guard let arr = value as? [Any] else { return false }
                for element in arr {
                    guard let dict = element as? [String: Any] else { return false }
                    if !validateJSONNode(dict, requiredDictKeys: requiredDictKeys) { return false }
                }
                continue
            }

            // Keys known to be dicts must actually be dicts.
            if requiredDictKeys.contains(key) {
                guard let dict = value as? [String: Any] else { return false }
                if !validateJSONNode(dict, requiredDictKeys: requiredDictKeys) { return false }
                continue
            }

            // Any other value — recurse if it's a container.
            if !validateAnyValue(value, requiredDictKeys: requiredDictKeys) { return false }
        }
        return true
    }

    /// Validates a dictionary node recursively.
    private static func validateJSONNode(_ dict: [String: Any], requiredDictKeys: Set<String>) -> Bool {
        for (key, value) in dict {
            if requiredDictKeys.contains(key) {
                guard let nested = value as? [String: Any] else { return false }
                if !validateJSONNode(nested, requiredDictKeys: requiredDictKeys) { return false }
            } else if !validateAnyValue(value, requiredDictKeys: requiredDictKeys) {
                return false
            }
        }
        return true
    }

    /// Validates that a JSON value is a legal JSON leaf or recursively valid container.
    private static func validateAnyValue(_ value: Any, requiredDictKeys: Set<String>) -> Bool {
        switch value {
        case is String, is NSNumber, is NSNull:
            return true
        case let dict as [String: Any]:
            return validateJSONNode(dict, requiredDictKeys: requiredDictKeys)
        case let arr as [Any]:
            return arr.allSatisfy { validateAnyValue($0, requiredDictKeys: requiredDictKeys) }
        default:
            // Unknown type in JSON tree — reject.
            return false
        }
    }
}
