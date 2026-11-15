import Foundation

extension NMEASimulator {

    // MARK: - Persistence & Mirror

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

    func makeSettingsSnapshot() -> SimulatorSettings {
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

    func apply(settings: SimulatorSettings) {
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
}
