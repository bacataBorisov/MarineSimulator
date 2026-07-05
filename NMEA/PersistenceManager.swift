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

        // Validate critical nested fields are dictionaries, not scalars
        // (guards against schema migration corruption).
        let requiredDictKeys = ["sentenceToggles", "sensorToggles", "twd", "tws",
                                "speed", "depth", "heading", "gyroHeading", "gpsData",
                                "faultInjection", "sentenceIntervals", "perSentenceTalkerID",
                                "liveWeatherSettings", "waypointNavigation"]
        for key in requiredDictKeys {
            if let val = json[key], !(val is [String: Any]) {
                print("Persisted settings field '\(key)' has unexpected type — resetting to defaults.")
                userDefaults.removeObject(forKey: Keys.simulatorSettings)
                return nil
            }
        }

        // outputEndpoints must be an array of dictionaries, not a scalar.
        if let val = json["outputEndpoints"], !(val is [[String: Any]]) {
            print("Persisted settings field 'outputEndpoints' has unexpected type — resetting to defaults.")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }

        do {
            return try JSONDecoder().decode(SimulatorSettings.self, from: data)
        } catch {
            print("Failed to restore simulator settings: \(error)")
            userDefaults.removeObject(forKey: Keys.simulatorSettings)
            return nil
        }
    }
}
