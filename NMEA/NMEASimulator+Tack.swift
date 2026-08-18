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

    func scheduleTackTimer() {
        tackAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: Self.tackAnimationTickInterval, repeats: true) { [weak self] _ in
            self?.advanceTackAnimation(at: Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        tackAnimationTimer = timer
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
