import Foundation

extension NMEASimulator {

    // MARK: - Tack

    /// Whether a tack animation is currently driving heading / gyro.
    var isTackInProgress: Bool {
        tackAnimationState != nil
    }

    /// Tack needs wind direction and at least one heading source (gyro and/or compass).
    var canExecuteTackManeuver: Bool {
        sensorToggles.hasAnemometer && (sensorToggles.hasGyro || sensorToggles.hasCompass)
    }

    /// Tack onto the opposite tack through the bow. Explicit side commands use `beginManeuver`.
    func beginTackManeuver() {
        beginAutomaticManeuver(.tack)
    }

    /// Gybe onto the opposite tack through the stern. Explicit side commands use `beginManeuver`.
    func beginGybeManeuver() {
        beginAutomaticManeuver(.gybe)
    }

    /// The named side is the destination tack. A command for the tack the boat is already on is unavailable.
    /// The command that is already driving heading stays available so its button can read “In progress”.
    func maneuverCommandIsAvailable(_ command: ManeuverCommand) -> Bool {
        if let active = activeManeuver, isTackInProgress, active.kind == command.kind, active.side == command.side {
            return true
        }
        guard canExecuteTackManeuver, let heading = maneuverReferenceHeading() else { return false }
        let wind = twd.value ?? twd.centerValue
        let speed = tws.value ?? tws.centerValue
        return boatProfile.sailingProfile.rejectionReason(
            for: command,
            trueHeading: heading,
            trueWindDirection: wind,
            trueWindSpeedKnots: speed
        ) == nil
    }

    var liveSailingState: ResolvedSailingState {
        let heading = maneuverReferenceHeading() ?? gpsData.courseOverGround
        let wind = twd.value ?? twd.centerValue
        let speed = tws.value ?? tws.centerValue
        return boatProfile.sailingProfile.resolve(
            trueHeading: heading,
            trueWindDirection: wind,
            trueWindSpeedKnots: speed
        )
    }

    var sailingPolicyExplanation: String? {
        boatProfile.sailingProfile.standingPolicyText(at: liveSailingState.pointOfSail)
    }

    /// Absolute true wind angle the next tack or gybe will keep.
    var maneuverAbsoluteTrueWindAngle: Double? {
        guard let heading = maneuverReferenceHeading() else { return nil }
        let wind = normalizeAngle(twd.value ?? twd.centerValue)
        return abs(calculateShortestRotation(from: heading, to: wind))
    }

    private func maneuverReferenceHeading() -> Double? {
        let variation = simulatedMagneticVariation(for: gpsData, at: Date())
        return resolvedTrueHeading(
            magneticHeading: heading.value,
            gyroHeading: gyroHeading.value,
            variation: variation
        ) ?? normalizeAngle(gpsData.courseOverGround)
    }

    func beginManeuver(_ command: ManeuverCommand) {
        guard vesselAllowsSimulation else {
            maneuverRejectionReason = "Select a vessel before starting a maneuver."
            return
        }
        guard canExecuteTackManeuver else { return }
        let run: () -> Void = { [weak self] in
            self?.beginHeadingManeuverOnMain(.explicit(command))
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// Stops a heading maneuver and keeps the heading where it is.
    func cancelManeuver() {
        let run: () -> Void = { [weak self] in
            self?.cancelManeuverOnMain(replacementHeading: nil)
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// Manual heading wins. The maneuver enters recovery and the new heading stays.
    func interruptManeuver(withTrueHeading trueHeading: Double) {
        let run: () -> Void = { [weak self] in
            self?.cancelManeuverOnMain(replacementHeading: trueHeading)
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    private enum HeadingManeuverRequest {
        case explicit(ManeuverCommand)
        case automatic(ManeuverKind)
    }

    private func beginAutomaticManeuver(_ kind: ManeuverKind) {
        guard vesselAllowsSimulation else {
            maneuverRejectionReason = "Select a vessel before starting a maneuver."
            return
        }
        guard canExecuteTackManeuver else { return }
        let run: () -> Void = { [weak self] in
            self?.beginHeadingManeuverOnMain(.automatic(kind))
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// Samples the heading the wire is already using, on the simulation queue, then
    /// leaves the simulation tick as the only heading writer.
    private func beginHeadingManeuverOnMain(_ request: HeadingManeuverRequest) {
        tackAnimationTimer?.invalidate()
        tackAnimationTimer = nil

        let mainMagnetic = heading.value
        let mainGyro = gyroHeading.value
        let mainTwd = twd.value ?? twd.centerValue
        let mainTws = tws.value ?? tws.centerValue
        let mainGPS = gpsData
        let profile = boatProfile
        let hasGyro = sensorToggles.hasGyro
        let hasCompass = sensorToggles.hasCompass
        let existing = activeManeuver
        let settings = maneuverSettings

        let start: TackStart = simulationQueue.sync {
            makeTackCommand(
                magnetic: transmitRuntime?.heading.value ?? mainMagnetic,
                gyro: transmitRuntime?.gyroHeading.value ?? mainGyro,
                twd: transmitRuntime?.twd.value ?? mainTwd,
                tws: transmitRuntime?.tws.value ?? mainTws,
                gps: transmitRuntime?.gpsData ?? mainGPS,
                profile: profile,
                hasGyro: hasGyro,
                hasCompass: hasCompass,
                request: request,
                existing: transmitRuntime?.activeManeuver ?? existing,
                settings: settings
            )
        }
        switch start {
        case .ignored:
            return
        case .rejected(let reason):
            maneuverRejectionReason = reason
            return
        case .command(let command):
            maneuverRejectionReason = nil
            activeManeuver = command.maneuver
            vesselObservation.maneuverPhase = .inProgress
            vesselObservation.maneuverKind = command.maneuver.kind
            tackAnimationState = TackAnimationState(
                startDate: command.maneuver.startedAt,
                duration: command.maneuver.duration,
                fromTrueHeading: command.maneuver.fromTrueHeading,
                toTrueHeading: command.maneuver.toTrueHeading
            )
            applySimulatedTrueHeading(command.maneuver.fromTrueHeading, at: command.maneuver.startedAt)
            syncInputMirror()
        }
    }

    private enum TackStart {
        case command(TackCommand)
        case ignored
        case rejected(String)
    }

    private struct TackCommand {
        var maneuver: ActiveManeuver
    }

    private func makeTackCommand(
        magnetic: Double?,
        gyro: Double?,
        twd: Double,
        tws: Double,
        gps: GPSData,
        profile: BoatProfile,
        hasGyro: Bool,
        hasCompass: Bool,
        request: HeadingManeuverRequest,
        existing: ActiveManeuver?,
        settings: ManeuverOperatorSettings
    ) -> TackStart {
        let now = Date()
        let variation = simulatedMagneticVariation(for: gps, at: now)
        let currentTrue = resolvedTrueHeading(
            magneticHeading: magnetic,
            gyroHeading: gyro,
            variation: variation
        ) ?? normalizeAngle(gps.courseOverGround)

        let twdDeg = normalizeAngle(twd)
        guard let resolved = resolvedCommand(request, from: currentTrue, wind: twdDeg) else {
            let probe: ManeuverCommand
            switch request {
            case .explicit(let command):
                probe = command
            case .automatic(let kind):
                probe = kind == .tack ? .tack(.port) : .gybe(.port)
            }
            return .rejected(profile.sailingProfile.rejectionReason(
                for: probe,
                trueHeading: currentTrue,
                trueWindDirection: twdDeg,
                trueWindSpeedKnots: tws
            ) ?? "The tack is ambiguous, so no maneuver was started.")
        }
        if let existing, existing.drivesHeading, existing.kind == resolved.kind, existing.side == resolved.side {
            return .ignored
        }
        if let reason = profile.sailingProfile.rejectionReason(
            for: resolved,
            trueHeading: currentTrue,
            trueWindDirection: twdDeg,
            trueWindSpeedKnots: tws
        ) {
            return .rejected(reason)
        }

        guard let plan = SimulationEngine.maneuverPlan(
            command: resolved,
            fromHeading: currentTrue,
            trueWindDirection: twdDeg
        ) else {
            return .rejected("The turn is too small.")
        }
        let target = plan.target
        let turnDelta = plan.turnDelta
        let settings = settings.sanitized()
        let duration = maneuverDuration(kind: resolved.kind, turnSize: abs(turnDelta), settings: settings)
        let maneuver = ActiveManeuver(
            kind: resolved.kind,
            side: resolved.side,
            startedAt: now,
            duration: duration,
            fromTrueHeading: currentTrue,
            toTrueHeading: target,
            trueWindDirection: twdDeg,
            turnDelta: turnDelta,
            drivesHeading: true
        )
        let magneticCommand = hasCompass ? normalizeAngle(currentTrue - variation) : magnetic
        installTackHeading(
            trueHeading: currentTrue,
            magneticHeading: magneticCommand,
            hasGyro: hasGyro,
            hasCompass: hasCompass,
            maneuver: maneuver
        )
        return .command(TackCommand(maneuver: maneuver))
    }

    private func resolvedCommand(
        _ request: HeadingManeuverRequest,
        from heading: Double,
        wind: Double
    ) -> ManeuverCommand? {
        switch request {
        case .explicit(let command):
            return command
        case .automatic(let kind):
            guard let tack = SimulationEngine.currentTack(trueHeading: heading, trueWindDirection: wind) else {
                return nil
            }
            let side: ManeuverSide = tack == .port ? .starboard : .port
            return kind == .tack ? .tack(side) : .gybe(side)
        }
    }

    private func maneuverDuration(kind: ManeuverKind, turnSize: Double, settings: ManeuverOperatorSettings) -> TimeInterval {
        switch kind {
        case .tack where settings.usesTackDuration:
            return settings.tackDurationSeconds
        case .gybe where settings.usesGybeDuration:
            return settings.gybeDurationSeconds
        default:
            return (6 + turnSize / 18 * 10).clamped(to: 6...20)
        }
    }

    @discardableResult
    func adoptManeuverPublication(_ runtime: SimulationState) -> Bool {
        let started = activeManeuver?.startedAt ?? tackAnimationState?.startDate
        if let started, let tick = runtime.lastSimulationTickDate, tick < started,
           runtime.activeManeuver?.drivesHeading != true {
            return false
        }
        guard let maneuver = runtime.activeManeuver, maneuver.drivesHeading else {
            activeManeuver = runtime.activeManeuver
            tackAnimationState = nil
            return true
        }
        activeManeuver = maneuver
        tackAnimationState = TackAnimationState(
            startDate: maneuver.startedAt,
            duration: maneuver.duration,
            fromTrueHeading: maneuver.fromTrueHeading,
            toTrueHeading: maneuver.toTrueHeading
        )
        return true
    }

    private func cancelManeuverOnMain(replacementHeading: Double?) {
        tackAnimationTimer?.invalidate()
        tackAnimationTimer = nil
        tackAnimationState = nil
        let kind = activeManeuver?.kind ?? vesselObservation.maneuverKind
        activeManeuver = nil
        if vesselObservation.maneuverPhase == .inProgress {
            vesselObservation.maneuverPhase = .recovery
            vesselObservation.maneuverKind = kind
        } else if replacementHeading == nil, vesselObservation.maneuverPhase == .recovery {
            vesselObservation.maneuverPhase = .idle
            vesselObservation.maneuverKind = nil
        }
        if let replacementHeading {
            applySimulatedTrueHeading(replacementHeading, at: Date())
        }
        simulationQueue.sync {
            guard var runtime = transmitRuntime else { return }
            runtime.activeManeuver = nil
            runtime.publishManeuverHeadingSetpoint = false
            if let replacementHeading {
                if sensorToggles.hasGyro {
                    runtime.gyroHeading.value = replacementHeading
                    runtime.gyroHeading.centerValue = replacementHeading.clamped(to: runtime.gyroHeading.range)
                }
                runtime.vesselTruth.trueHeading = replacementHeading
            }
            if runtime.vesselObservation.maneuverPhase == .inProgress {
                runtime.vesselObservation.maneuverPhase = .recovery
                runtime.vesselObservation.maneuverKind = kind
                runtime.recoveryStartedAt = Date()
            } else if replacementHeading == nil, runtime.vesselObservation.maneuverPhase == .recovery {
                runtime.vesselObservation.maneuverPhase = .idle
                runtime.vesselObservation.maneuverKind = nil
                runtime.recoveryStartedAt = nil
            }
            transmitRuntime = runtime
        }
        syncInputMirror()
    }

    /// Called on the simulation queue. Keeps the next tick on the heading HDT already uses.
    private func installTackHeading(
        trueHeading: Double,
        magneticHeading: Double?,
        hasGyro: Bool,
        hasCompass: Bool,
        maneuver: ActiveManeuver
    ) {
        if var runtime = transmitRuntime {
            runtime.activeManeuver = maneuver
            runtime.vesselObservation.maneuverPhase = .inProgress
            runtime.vesselObservation.maneuverKind = maneuver.kind
            if hasGyro {
                runtime.gyroHeading.value = trueHeading
                runtime.gyroHeading.centerValue = trueHeading.clamped(to: runtime.gyroHeading.range)
            }
            if hasCompass, let magneticHeading {
                runtime.heading.value = magneticHeading
                runtime.heading.centerValue = magneticHeading.clamped(to: runtime.heading.range)
                runtime.vesselTruth.magneticHeading = magneticHeading
            }
            runtime.vesselTruth.trueHeading = trueHeading
            transmitRuntime = runtime
        }

        writeTackCommandToMirror(
            trueHeading: trueHeading,
            magneticHeading: magneticHeading,
            hasGyro: hasGyro,
            hasCompass: hasCompass
        )
    }

    func advanceTackAnimation(at date: Date) {
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

    func applySimulatedTrueHeading(_ trueDeg: Double, at date: Date) {
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
}
