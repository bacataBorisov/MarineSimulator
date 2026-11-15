import Foundation

extension SimulationEngine {

    // MARK: - Boat speed estimation & maneuvers

    static func referencePolar(for config: SimulationConfig) -> PolarModel {
        PolarModel(profile: config.boatProfile)
    }

    static func hiddenPolar(for state: SimulationState, config: SimulationConfig) -> PolarModel {
        PolarModel(profile: state.hiddenPolarOverride ?? config.boatProfile)
    }

    /// First-order step. `tau <= 0` assigns the target immediately.
    static func stepSpeed(current: Double, target: Double, deltaTime: TimeInterval, tau: TimeInterval) -> Double {
        guard deltaTime > 0, tau > 0, tau.isFinite, target.isFinite, current.isFinite else {
            return target.isFinite ? target : current
        }
        return target + (current - target) * exp(-deltaTime / tau)
    }

    static func classifyManeuver(
        fromHeading: Double,
        toHeading: Double,
        trueWindDirection: Double
    ) -> ManeuverKind? {
        let wind = normalizeAngle(trueWindDirection)
        if shortArcContains(start: fromHeading, end: toHeading, angle: wind) {
            return .tack
        }
        if shortArcContains(start: fromHeading, end: toHeading, angle: normalizeAngle(wind + 180)) {
            return .gybe
        }
        return nil
    }

    /// Sailing tack from signed true wind angle `normalize(TWD − HDG)`.
    /// `(0°, 180°)` is starboard, wind on the starboard side. `(180°, 360°)` is port.
    /// Head-to-wind and dead downwind, within half a degree, are not a tack.
    static func currentTack(trueHeading: Double, trueWindDirection: Double) -> ManeuverSide? {
        let trueWindAngle = normalizeAngle(trueWindDirection - trueHeading)
        if trueWindAngle <= 0.5 || trueWindAngle >= 359.5 { return nil }
        if trueWindAngle >= 179.5 && trueWindAngle <= 180.5 { return nil }
        return trueWindAngle < 180 ? .starboard : .port
    }

    /// Heading reflected across the captured true wind. Absolute true wind angle is unchanged.
    static func mirroredTrueHeading(trueWindDirection: Double, trueHeading: Double) -> Double {
        normalizeAngle(2 * normalizeAngle(trueWindDirection) - trueHeading)
    }

    /// Destination tack is `command.side`. The current tack, head-to-wind, and dead downwind return nil.
    /// A tack sweeps through the captured true wind. A gybe sweeps through the captured downwind axis.
    /// `turnDelta` is the unwrapped sweep, including the long way around.
    static func maneuverPlan(
        command: ManeuverCommand,
        fromHeading: Double,
        trueWindDirection: Double
    ) -> (target: Double, turnDelta: Double)? {
        let wind = normalizeAngle(trueWindDirection)
        let start = normalizeAngle(fromHeading)
        guard let tack = currentTack(trueHeading: start, trueWindDirection: wind), tack != command.side else {
            return nil
        }
        let target = mirroredTrueHeading(trueWindDirection: wind, trueHeading: start)
        let axis = command.kind == .tack ? wind : normalizeAngle(wind + 180)
        guard let turnDelta = maneuverTurnDelta(from: start, to: target, mustContain: axis) else {
            return nil
        }
        return (target, turnDelta)
    }

    /// Signed sweep whose interior contains `axis`. Nil when the turn is under half a degree or neither arc contains it.
    static func maneuverTurnDelta(from start: Double, to end: Double, mustContain axis: Double) -> Double? {
        let short = calculateShortestRotation(from: start, to: end)
        guard abs(short) > 0.5 else { return nil }
        if arcContains(start: start, delta: short, angle: axis) {
            return short
        }
        let long = short > 0 ? short - 360 : short + 360
        guard abs(long) > 0.5, arcContains(start: start, delta: long, angle: axis) else { return nil }
        return long
    }

    static func maneuverHeading(maneuver: ActiveManeuver, at timestamp: Date) -> Double {
        let duration = maneuver.duration
        guard duration > 0 else { return normalizeAngle(maneuver.fromTrueHeading + maneuver.turnDelta) }
        let progress = min(1, max(0, timestamp.timeIntervalSince(maneuver.startedAt) / duration))
        let smooth = progress * progress * (3 - 2 * progress)
        return normalizeAngle(maneuver.fromTrueHeading + maneuver.turnDelta * smooth)
    }

    static func arcContains(start: Double, delta: Double, angle: Double) -> Bool {
        guard abs(delta) > 0.5 else { return false }
        let short = calculateShortestRotation(from: start, to: normalizeAngle(angle))
        let offset = delta > 0
            ? (short >= -0.05 ? short : short + 360)
            : (short <= 0.05 ? short : short - 360)
        if delta > 0 {
            return offset > 0.5 && offset < delta - 0.5
        }
        return offset < -0.5 && offset > delta + 0.5
    }

    static func applyDrivenManeuverHeading(
        state: inout SimulationState,
        config: SimulationConfig,
        at timestamp: Date
    ) -> Bool {
        guard let maneuver = state.activeManeuver, maneuver.drivesHeading else { return false }
        let end = maneuver.startedAt.addingTimeInterval(maneuver.duration)
        let trueHeading = timestamp >= end
            ? normalizeAngle(maneuver.toTrueHeading)
            : maneuverHeading(maneuver: maneuver, at: timestamp)
        let variation = simulatedMagneticVariation(for: state.gpsData, at: timestamp)
        let magnetic = normalizeAngle(trueHeading - variation)
        state.vesselTruth.magneticHeading = magnetic
        state.vesselTruth.trueHeading = trueHeading
        if config.sensorToggles.hasGyro {
            state.gyroHeading.value = trueHeading
            state.gyroHeading.centerValue = trueHeading.clamped(to: state.gyroHeading.range)
        }
        if config.sensorToggles.hasCompass {
            state.heading.value = magnetic
            state.heading.centerValue = magnetic.clamped(to: state.heading.range)
        }
        state.publishManeuverHeadingSetpoint = true
        return true
    }

    static func estimatedBoatSpeed(
        trueHeading: Double,
        state: SimulationState,
        config: SimulationConfig
    ) -> Double? {
        guard let trueWindSpeed = state.environmentTruth.trueWindSpeedKnots else {
            return nil
        }

        let trueWindDirection = state.environmentTruth.trueWindDirection ?? state.gpsData.courseOverGround
        let trueWindAngle = abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))
        let baseSpeed = config.boatProfile.estimatedBoatSpeed(
            trueWindSpeedKnots: trueWindSpeed,
            trueWindAngleDegrees: trueWindAngle
        )
        guard let baseSpeed else { return nil }

        let seaStatePenalty = config.weatherSourceMode == .liveWeather ? 0.96 : 1.0
        let variationPenalty = max(0.88, 1.0 - (state.speed.offset / 100))
        return (baseSpeed * seaStatePenalty * variationPenalty).clamped(to: SimulatedValueType.speedLog.defaultRange)
    }

    static func hiddenTargetSpeedKnots(
        trueHeading: Double,
        state: SimulationState,
        config: SimulationConfig,
        at timestamp: Date
    ) -> Double? {
        guard let trueWindSpeed = state.environmentTruth.trueWindSpeedKnots else {
            return nil
        }
        let trueWindDirection = state.environmentTruth.trueWindDirection ?? state.gpsData.courseOverGround
        let trueWindAngle = abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))
        guard let hiddenSpeed = hiddenPolar(for: state, config: config).targetSpeedKnots(
            trueWindSpeedKnots: trueWindSpeed,
            trueWindAngleDegrees: trueWindAngle
        ) else { return nil }
        let seaStatePenalty = config.weatherSourceMode == .liveWeather ? 0.96 : 1.0
        let variationPenalty = max(0.88, 1.0 - (state.speed.offset / 100))
        let factors = state.performance.sanitized()
        let retention = maneuverRetention(state: state, at: timestamp, parameters: factors)
        return (hiddenSpeed * seaStatePenalty * variationPenalty
            * factors.hullFactor * factors.sailFactor * factors.trimEfficiency * factors.seaStateFactor * retention)
            .clamped(to: SimulatedValueType.speedLog.defaultRange)
    }

    static func respondedSpeed(
        current: Double,
        target: Double,
        deltaTime: TimeInterval,
        parameters: PerformanceParameters
    ) -> Double {
        let clean = parameters.sanitized()
        guard clean.speedResponse == .firstOrder else { return target }
        guard deltaTime > 0 else { return current }
        let tau = target >= current
            ? clean.accelerationTimeConstantSeconds
            : clean.decelerationTimeConstantSeconds
        return stepSpeed(current: current, target: target, deltaTime: deltaTime, tau: tau)
            .clamped(to: SimulatedValueType.speedLog.defaultRange)
    }

    static func maneuverRetention(
        state: SimulationState,
        at timestamp: Date,
        parameters: PerformanceParameters
    ) -> Double {
        guard state.vesselObservation.maneuverPhase == .inProgress, let maneuver = state.activeManeuver else {
            return 1
        }
        let minimum = maneuver.kind == .gybe ? parameters.gybeSpeedRetention : parameters.tackSpeedRetention
        guard maneuver.duration > 0 else { return minimum }
        let progress = min(1, max(0, timestamp.timeIntervalSince(maneuver.startedAt) / maneuver.duration))
        return 1 - (1 - minimum) * sin(progress * Double.pi)
    }

    static func applyDuePerformanceChanges(state: inout SimulationState, at timestamp: Date) {
        state.performance = state.performance.sanitized()
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else { return }
        var remaining: [ScheduledPerformanceChange] = []
        for change in state.scheduledPerformanceChanges.sorted(by: { $0.simulationTime < $1.simulationTime }) {
            guard change.simulationTime.timeIntervalSinceReferenceDate.isFinite else { continue }
            if change.simulationTime <= timestamp {
                state.performance = change.parameters.sanitized()
            } else {
                remaining.append(change)
            }
        }
        state.scheduledPerformanceChanges = remaining
    }

    static func updateManeuverPhase(
        state: inout SimulationState,
        animationInProgress: Bool,
        at timestamp: Date
    ) {
        if let maneuver = state.activeManeuver, maneuver.drivesHeading {
            let end = maneuver.startedAt.addingTimeInterval(maneuver.duration)
            if timestamp < end {
                state.vesselObservation.maneuverPhase = .inProgress
                state.vesselObservation.maneuverKind = maneuver.kind
                state.recoveryStartedAt = nil
                return
            }
            state.vesselObservation.maneuverPhase = .recovery
            state.vesselObservation.maneuverKind = maneuver.kind
            state.recoveryStartedAt = timestamp
            state.activeManeuver = nil
            return
        }

        if animationInProgress, state.activeManeuver != nil {
            state.vesselObservation.maneuverPhase = .inProgress
            state.vesselObservation.maneuverKind = state.activeManeuver?.kind
            state.recoveryStartedAt = nil
            return
        }

        if state.vesselObservation.maneuverPhase == .inProgress {
            state.vesselObservation.maneuverPhase = .recovery
            state.recoveryStartedAt = timestamp
            state.activeManeuver = nil
            return
        }

        guard state.vesselObservation.maneuverPhase == .recovery else { return }
        let parameters = state.performance.sanitized()
        let elapsed = timestamp.timeIntervalSince(state.recoveryStartedAt ?? timestamp)
        let tau = max(parameters.accelerationTimeConstantSeconds, parameters.decelerationTimeConstantSeconds)
        let limit = parameters.speedResponse == .instant ? 0 : max(3 * tau, 1)
        if elapsed > 0, elapsed >= limit {
            state.vesselObservation.maneuverPhase = .idle
            state.vesselObservation.maneuverKind = nil
            state.recoveryStartedAt = nil
        }
    }

    private static func shortArcContains(start: Double, end: Double, angle: Double) -> Bool {
        let sweep = calculateShortestRotation(from: start, to: end)
        guard abs(sweep) > 0.5 else { return false }
        let toAngle = calculateShortestRotation(from: start, to: normalizeAngle(angle))
        if sweep > 0 {
            return toAngle > 0.5 && toAngle < sweep - 0.5
        }
        return toAngle < -0.5 && toAngle > sweep + 0.5
    }
}
