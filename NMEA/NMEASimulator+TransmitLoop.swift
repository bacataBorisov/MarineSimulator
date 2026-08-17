import Foundation

extension NMEASimulator {

    // MARK: - Off-main transmit loop

    func startSimulationTimer() {
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

    func stopSimulationTimer() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    /// Main-thread convenience: captures config directly from `self`.
    func captureSimulationConfig() -> SimulationConfig {
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

    func applyRuntimeToMain(_ runtime: SimulationState, flushConsoleImmediately: Bool) {
        #if DEBUG
        HangProbe.tick(.apply)
        HangProbe.enter("apply")
        defer { HangProbe.leave("apply") }
        #endif
        let applyStarted = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - applyStarted
            runtimeApplyLock.lock()
            lastApplyDuration = duration
            runtimeApplyLock.unlock()
        }
        isApplyingSimulationTick = true
        // Only write changed fields — unconditional 20 Hz assignment of every SimulatedValue
        // floods Observation and makes live sliders fight the UI update storm.
        applyGeneratedOutput(runtime.twd, to: &twd)
        applyGeneratedOutput(runtime.tws, to: &tws)
        applyGeneratedOutput(runtime.speed, to: &speed)
        applyGeneratedOutput(runtime.depth, to: &depth)
        applyGeneratedOutput(runtime.seaTemp, to: &seaTemp)
        applyGeneratedOutput(runtime.airTemp, to: &airTemp)
        applyGeneratedOutput(runtime.humidity, to: &humidity)
        applyGeneratedOutput(runtime.barometer, to: &barometer)
        applyGeneratedOutput(runtime.heading, to: &heading)
        applyGeneratedOutput(runtime.gyroHeading, to: &gyroHeading)
        applyGeneratedGPS(runtime.gpsData)
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

    /// Engine owns `value`; the user owns setpoint (`centerValue` / `offset`).
    private func applyGeneratedOutput(_ incoming: SimulatedValue, to current: inout SimulatedValue) {
        if current.value != incoming.value {
            current.value = incoming.value
        }
    }

    private func applyGeneratedGPS(_ incoming: GPSData) {
        if isEditingGPSCoordinates {
            var next = gpsData
            next.speedOverGround = incoming.speedOverGround
            next.courseOverGround = incoming.courseOverGround
            if gpsData != next { gpsData = next }
            return
        }
        if gpsData != incoming { gpsData = incoming }
    }

    /// Latest-wins UI frame after the current run-loop turn. A `Timer` on `.common`
    /// fires during MapKit/SwiftUI layout and can freeze the main thread.
    private func publishDisplayFrame() {
        #if DEBUG
        HangProbe.tick(.display)
        HangProbe.enter("display")
        defer { HangProbe.leave("display") }
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
        let delay = lastApplyDuration > 0.05
            ? Self.displayPublishInterval * 2
            : Self.displayPublishInterval
        if needsSchedule {
            let work = DispatchWorkItem { [weak self] in
                self?.publishDisplayFrame()
            }
            displayPublishWorkItem = work
            runtimeApplyLock.unlock()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: work
            )
        } else {
            runtimeApplyLock.unlock()
        }
    }

    func cancelDisplayPublish() {
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
        #if DEBUG
        HangProbe.enter("console.flush")
        defer { HangProbe.leave("console.flush") }
        #endif
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

    func runTransmitSimulationCycle(at timestamp: Date) {
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

    func mapDashboardBearingBeforeFirstSnapshot() -> Double {
        if sensorToggles.hasGyro {
            return normalizeAngle(gyroHeading.value ?? gyroHeading.centerValue)
        }
        if sensorToggles.hasCompass {
            return normalizeAngle(heading.value ?? heading.centerValue)
        }
        return normalizeAngle(gpsData.courseOverGround)
    }

}
