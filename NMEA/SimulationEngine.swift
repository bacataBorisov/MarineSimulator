import Foundation

/// Pure simulation logic that operates on `SimulationState` + `SimulationConfig`.
///
/// Every method is static and side-effect-free (apart from mutating the `inout` state).
/// `NMEASimulator` delegates here for both the main-thread single-shot path and the
/// off-main fast transmit loop, eliminating the duplicated method pairs.
enum SimulationEngine {

    /// Manual environment and vessel redraw. Independent of the 20 Hz physics tick and of per-sentence NMEA rates.
    static let environmentEvolutionInterval: TimeInterval = 1

    // MARK: - Tick

    /// Advance all simulated sensor values by one step and return a snapshot.
    ///
    /// - Parameters:
    ///   - state: Mutable simulation state (sensors, GPS, distances, weather noise).
    ///   - config: Read-only configuration (toggles, modes, boat profile, …).
    ///   - timestamp: The wall-clock time of this tick.
    ///   - liveWeatherValueGenerator: Closure the caller provides to generate jittered
    ///     live-weather sensor values (keeps the random-jitter helper on `NMEASimulator`).
    /// - Returns: An immutable `SimulationSnapshot` ready for sentence builders.
    static func tickSimulation(
        state: inout SimulationState,
        config: SimulationConfig,
        at timestamp: Date,
        liveWeatherValueGenerator: (_ base: Double?, _ jitter: Double, _ range: ClosedRange<Double>, _ wraps: Bool) -> Double?
    ) -> SimulationSnapshot {
        // Only manually evolved experiment values use this generator. Live weather remains
        // provider-driven, and unseeded operator sessions preserve their existing randomness.
        var experimentRandomGenerator = state.experimentRandomGenerator
        defer { state.experimentRandomGenerator = experimentRandomGenerator }
        let deltaTime = resolvedDeltaTime(state: state, for: timestamp)
        let evolveSensors = shouldAdvance(
            since: state.lastSensorEvolutionDate,
            at: timestamp,
            interval: Self.environmentEvolutionInterval
        )

        // --- Weather ---
        if config.weatherSourceMode == .liveWeather {
            if let liveWeather = config.latestLiveWeather {
                syncLiveWeatherWindNoiseBaselineIfNeeded(
                    state: &state,
                    fetchedAt: liveWeather.fetchedAt
                )
                evolveLiveWeatherWindNoise(state: &state, deltaTime: deltaTime)

                if let baseDir = liveWeather.trueWindDirection {
                    state.twd.value = normalizeAngle(baseDir + state.liveWeatherWindDirectionOffsetDeg)
                } else {
                    state.twd.value = nil
                }
                if let baseKt = liveWeather.trueWindSpeedKnots {
                    state.tws.value = (baseKt + state.liveWeatherWindSpeedOffsetKt)
                        .clamped(to: SimulatedValueType.windSpeed.defaultRange)
                } else {
                    state.tws.value = nil
                }
                if evolveSensors {
                    state.seaTemp.value = liveWeatherValueGenerator(
                        liveWeather.seaSurfaceTemperatureCelsius,
                        0.3,
                        SimulatedValueType.seaTemp.defaultRange,
                        false
                    )
                    ensureMeasurementGenerator(state: &state)
                    state.airTemp.value = jitteredEnvironmentValue(
                        base: liveWeather.airTemperatureCelsius,
                        jitter: 0.4,
                        range: SimulatedValueType.airTemp.defaultRange,
                        state: &state
                    )
                    state.humidity.value = jitteredEnvironmentValue(
                        base: liveWeather.relativeHumidityPercent,
                        jitter: 1.8,
                        range: SimulatedValueType.humidity.defaultRange,
                        state: &state
                    )
                    state.barometer.value = jitteredEnvironmentValue(
                        base: liveWeather.airPressureHectopascals,
                        jitter: 0.8,
                        range: SimulatedValueType.barometer.defaultRange,
                        state: &state
                    )
                } else {
                    state.seaTemp.value = state.environmentTruth.seaTemperatureCelsius
                    state.airTemp.value = state.environmentTruth.airTemperatureCelsius
                    state.humidity.value = state.environmentTruth.relativeHumidityPercent
                    state.barometer.value = state.environmentTruth.airPressureHectopascals
                }
            } else {
                state.twd.value = nil
                state.tws.value = nil
                state.seaTemp.value = nil
                state.airTemp.value = nil
                state.humidity.value = nil
                state.barometer.value = nil
            }
            commitEnvironmentTruth(state: &state)
        } else if evolveSensors {
            state.twd.value = state.twd.generateRandomValue {
                nextRandomUnitInterval(using: &experimentRandomGenerator)
            }
            state.tws.value = state.tws.generateRandomValue {
                nextRandomUnitInterval(using: &experimentRandomGenerator)
            }
            state.seaTemp.value = state.seaTemp.generateRandomValue {
                nextRandomUnitInterval(using: &experimentRandomGenerator)
            }
            ensureMeasurementGenerator(state: &state)
            state.airTemp.value = state.airTemp.generateRandomValue {
                nextRandomUnitInterval(using: &state.measurementRandomGenerator)
            }
            state.humidity.value = state.humidity.generateRandomValue {
                nextRandomUnitInterval(using: &state.measurementRandomGenerator)
            }
            state.barometer.value = state.barometer.generateRandomValue {
                nextRandomUnitInterval(using: &state.measurementRandomGenerator)
            }
            commitEnvironmentTruth(state: &state)
        } else {
            projectEnvironmentTruth(state: &state)
        }
        hideDisabledEnvironmentMeasurements(state: &state, config: config)

        // --- Heading ---
        // The heading sample is physical. Compass and gyro switches only decide whether it is published.
        let headingVariation = simulatedMagneticVariation(for: state.gpsData, at: timestamp)
        if evolveSensors, !config.tackAnimationInProgress, state.activeManeuver?.drivesHeading != true {
            state.heading.value = state.heading.generateRandomValue {
                nextRandomUnitInterval(using: &experimentRandomGenerator)
            }
            state.vesselTruth.magneticHeading = state.heading.value
            if let magnetic = state.vesselTruth.magneticHeading {
                state.vesselTruth.trueHeading = normalizeAngle(magnetic + headingVariation)
            }
            if config.sensorToggles.hasGyro {
                state.gyroHeading.centerValue = state.vesselTruth.trueHeading.clamped(to: state.gyroHeading.range)
            }
        } else if config.tackAnimationInProgress {
            state.vesselTruth.magneticHeading = state.heading.value
        } else if state.vesselTruth.magneticHeading == nil {
            state.vesselTruth.magneticHeading = state.heading.value
        }
        if evolveSensors {
            state.depth.value = state.depth.generateRandomValue {
                nextRandomUnitInterval(using: &experimentRandomGenerator)
            }
            state.environmentTruth.depthMeters = state.depth.value
        } else {
            state.depth.value = state.environmentTruth.depthMeters
        }
        if !config.sensorToggles.hasEchoSounder {
            state.depth.value = nil
        }

        let maneuverDrivesHeading = applyDrivenManeuverHeading(state: &state, config: config, at: timestamp)
        if !maneuverDrivesHeading {
            state.publishManeuverHeadingSetpoint = false
        }
        publishHeadingInstruments(state: &state, config: config)

        // --- Speed & Movement ---
        let magneticVariation = simulatedMagneticVariation(for: state.gpsData, at: timestamp)
        let boatTrueHeading = resolvedSteeringTrueHeading(
            state: state,
            config: config,
            variation: magneticVariation
        )

        applyDuePerformanceChanges(state: &state, at: timestamp)
        updateManeuverPhase(state: &state, animationInProgress: config.tackAnimationInProgress, at: timestamp)
        state.vesselObservation.referenceProfile = config.boatProfile
        state.vesselObservation.sailConfiguration = state.sailConfiguration
        let windDirection = state.environmentTruth.trueWindDirection ?? state.twd.centerValue
        let windSpeed = state.environmentTruth.trueWindSpeedKnots ?? state.tws.centerValue
        state.vesselObservation.sailingState = config.boatProfile.sailingProfile.resolve(
            trueHeading: boatTrueHeading,
            trueWindDirection: windDirection,
            trueWindSpeedKnots: windSpeed
        )

        let truthProfile = state.hiddenPolarOverride ?? config.boatProfile
        if config.boatSpeedMode == .estimated, truthProfile.hasSpeedPolar {
            if let target = hiddenTargetSpeedKnots(
                trueHeading: boatTrueHeading,
                state: state,
                config: config,
                at: timestamp
            ) {
                let next = respondedSpeed(
                    current: state.vesselTruth.speedThroughWaterKnots ?? target,
                    target: target,
                    deltaTime: deltaTime,
                    parameters: state.performance
                )
                state.vesselTruth.speedThroughWaterKnots = next
                state.speed.value = config.sensorToggles.hasSpeedLog ? next : nil
            } else if state.performance.speedResponse == .instant {
                state.speed.value = nil
                state.vesselTruth.speedThroughWaterKnots = nil
            } else {
                state.speed.value = nil
            }
        } else if config.boatSpeedMode == .estimated {
            let held = state.vesselTruth.speedThroughWaterKnots ?? state.speed.value
            state.vesselTruth.speedThroughWaterKnots = held
            state.speed.value = config.sensorToggles.hasSpeedLog ? held : nil
        } else if evolveSensors {
            let sample = state.speed.generateRandomValue {
                nextRandomUnitInterval(using: &experimentRandomGenerator)
            }
            state.vesselTruth.speedThroughWaterKnots = sample
            state.speed.value = config.sensorToggles.hasSpeedLog ? sample : nil
        } else {
            if state.vesselTruth.speedThroughWaterKnots == nil {
                state.vesselTruth.speedThroughWaterKnots = state.speed.value
            }
            state.speed.value = config.sensorToggles.hasSpeedLog ? state.vesselTruth.speedThroughWaterKnots : nil
        }

        let keepThroughWaterSpeed = state.hiddenPolarOverride != nil && !truthProfile.hasSpeedPolar
        let waterSpeed = state.vesselTruth.speedThroughWaterKnots
            ?? (keepThroughWaterSpeed ? 0 : state.gpsData.speedOverGround)
        let movement = simulatedMovement(
            waterSpeed: waterSpeed,
            trueHeading: boatTrueHeading,
            at: timestamp,
            gpsData: state.gpsData
        )

        if state.lastAppliedGPSCoordinateGeneration != state.vesselTruth.acceptedCoordinateGeneration {
            state.vesselTruth.latitude = state.gpsData.latitude
            state.vesselTruth.longitude = state.gpsData.longitude
            state.vesselTruth.acceptedCoordinateGeneration = state.lastAppliedGPSCoordinateGeneration
        } else {
            state.gpsData.latitude = state.vesselTruth.latitude
            state.gpsData.longitude = state.vesselTruth.longitude
        }

        if deltaTime > 0 {
            state.gpsData.updatePosition(
                deltaTime: deltaTime,
                sog: movement.speedOverGround,
                cog: movement.courseOverGround
            )
        }

        state.vesselTruth.trueHeading = boatTrueHeading
        if keepThroughWaterSpeed {
            state.vesselTruth.speedThroughWaterKnots = state.speed.value ?? state.vesselTruth.speedThroughWaterKnots
        } else {
            state.vesselTruth.speedThroughWaterKnots = waterSpeed
        }
        state.vesselTruth.latitude = state.gpsData.latitude
        state.vesselTruth.longitude = state.gpsData.longitude
        state.vesselTruth.speedOverGroundKnots = state.gpsData.speedOverGround
        state.vesselTruth.courseOverGroundDegrees = state.gpsData.courseOverGround

        if config.sensorToggles.hasSpeedLog {
            state.totalLogDistanceNm += max(0, waterSpeed) * deltaTime / 3600
            state.totalTripDistanceNm += max(0, waterSpeed) * deltaTime / 3600
        }

        // --- Derived values ---
        let turnRate = computedTurnRate(
            currentHeading: boatTrueHeading,
            deltaTime: deltaTime,
            previousReference: &state.previousTurnReferenceHeading
        )
        let compassDeviation = simulatedCompassDeviation(heading: state.heading.value)
        let experimentPublication = recordExperimentMeasurement(
            state: &state,
            config: config,
            variation: magneticVariation,
            deviation: compassDeviation,
            at: timestamp
        )
        let gpsSignal = simulatedGPSSignal(for: state.gpsData, at: timestamp)

        let navTarget: NavigationTarget? = config.waypointNavigation.isActive ? NavigationTarget(
            originName: config.waypointNavigation.originName,
            destinationName: config.waypointNavigation.destinationName,
            originLatitude: config.waypointNavigation.originLatitude,
            originLongitude: config.waypointNavigation.originLongitude,
            destinationLatitude: config.waypointNavigation.destinationLatitude,
            destinationLongitude: config.waypointNavigation.destinationLongitude,
            arrivalRadiusNm: config.waypointNavigation.arrivalRadiusNm
        ) : nil

        let snapshot = SimulationSnapshot(
            timestamp: timestamp,
            windDirectionTrue: state.twd.value,
            windSpeedTrue: state.tws.value,
            magneticHeading: state.heading.value,
            gyroHeading: state.gyroHeading.value,
            magneticVariation: magneticVariation,
            compassDeviation: compassDeviation,
            boatSpeed: state.speed.value,
            depth: state.depth.value,
            seaTemperature: state.seaTemp.value,
            airTemperature: state.airTemp.value,
            relativeHumidity: state.humidity.value,
            airPressure: state.barometer.value,
            gpsData: state.gpsData,
            gpsSignal: gpsSignal,
            turnRate: turnRate,
            logDistanceNm: state.totalLogDistanceNm,
            tripDistanceNm: state.totalTripDistanceNm,
            navigationTarget: navTarget,
            experimentPublication: experimentPublication
        )

        state.latestSnapshot = snapshot
        state.lastSimulationTickDate = timestamp
        if evolveSensors {
            state.lastSensorEvolutionDate = timestamp
        }
        return snapshot
    }

    private static func nextRandomUnitInterval(
        using generator: inout ExperimentRandomGenerator?
    ) -> Double {
        guard var current = generator else {
            return Double.random(in: 0...1)
        }
        let value = current.nextUnitInterval()
        generator = current
        return value
    }

    // MARK: - Scheduling

    static func shouldAdvanceSimulation(
        state: SimulationState,
        at timestamp: Date,
        interval: TimeInterval
    ) -> Bool {
        shouldAdvance(since: state.lastSimulationTickDate, at: timestamp, interval: interval)
    }

    private static func shouldAdvance(
        since lastDate: Date?,
        at timestamp: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let lastDate else {
            return true
        }
        return timestamp.timeIntervalSince(lastDate) >= interval
    }

    static func effectiveInterval(
        for sentence: NMEASentenceType,
        config: SimulationConfig
    ) -> TimeInterval {
        if let configured = config.sentenceIntervals[sentence] {
            return configured
        }
        return config.interval
    }

    private static func commitEnvironmentTruth(state: inout SimulationState) {
        var next = state.environmentTruth
        next.trueWindDirection = state.twd.value
        next.trueWindSpeedKnots = state.tws.value
        next.seaTemperatureCelsius = state.seaTemp.value
        next.airTemperatureCelsius = state.airTemp.value
        next.relativeHumidityPercent = state.humidity.value
        next.airPressureHectopascals = state.barometer.value
        next.depthMeters = state.environmentTruth.depthMeters
        state.environmentTruth = next
    }

    private static func ensureMeasurementGenerator(state: inout SimulationState) {
        if state.measurementRandomGenerator == nil {
            state.measurementRandomGenerator = ExperimentRandomGenerator(seed: 0x6D34_4A11_5EED)
        }
    }

    private static func jitteredEnvironmentValue(
        base: Double?,
        jitter: Double,
        range: ClosedRange<Double>,
        state: inout SimulationState
    ) -> Double? {
        guard let base else { return nil }
        let unit = nextRandomUnitInterval(using: &state.measurementRandomGenerator)
        let offset = (unit * 2 - 1) * jitter
        return (base + offset).clamped(to: range)
    }

    /// One measurement for this timestamp. A repeated timestamp reuses the stored sample.
    private static func recordExperimentMeasurement(
        state: inout SimulationState,
        config: SimulationConfig,
        variation: Double,
        deviation: Double,
        at timestamp: Date
    ) -> ExperimentNavigationPublication? {
        guard var session = state.experimentInstruments else { return nil }
        if session.sampleTimestamp != timestamp || session.latest == nil {
            let truth = ExperimentSensorTruth(
                trueWindSpeedKnots: state.environmentTruth.trueWindSpeedKnots,
                trueHeadingDegrees: state.vesselTruth.trueHeading,
                trueWindDirectionDegrees: state.environmentTruth.trueWindDirection,
                speedThroughWaterKnots: state.vesselTruth.speedThroughWaterKnots,
                magneticVariationDegrees: variation,
                compassDeviationDegrees: deviation
            )
            let availability = InstrumentAvailability(
                trueHeadingInstrument: config.sensorToggles.hasGyro,
                magneticCompass: config.sensorToggles.hasCompass,
                apparentWind: config.sensorToggles.hasAnemometer,
                speedThroughWater: config.sensorToggles.hasSpeedLog
            )
            session.latest = session.model.measure(truth, errors: session.errors, availability: availability)
            session.sampleTimestamp = timestamp
            state.experimentInstruments = session
        }
        guard let latest = state.experimentInstruments?.latest else { return nil }
        return ExperimentInstrumentRuntime.publication(from: latest)
    }

    private static func publishHeadingInstruments(state: inout SimulationState, config: SimulationConfig) {
        state.heading.value = config.sensorToggles.hasCompass ? state.vesselTruth.magneticHeading : nil
        state.gyroHeading.value = config.sensorToggles.hasGyro ? state.vesselTruth.trueHeading : nil
    }

    /// Hide measurements for sensors that are off. Does not write ground truth.
    private static func hideDisabledEnvironmentMeasurements(state: inout SimulationState, config: SimulationConfig) {
        if !config.sensorToggles.hasAnemometer {
            state.twd.value = nil
            state.tws.value = nil
        }
        if !config.sensorToggles.hasWaterTempSensor {
            state.seaTemp.value = nil
        }
        if !config.sensorToggles.hasAirTempSensor {
            state.airTemp.value = nil
        }
        if !config.sensorToggles.hasHumidtySensor {
            state.humidity.value = nil
        }
        if !config.sensorToggles.hasBarometer {
            state.barometer.value = nil
        }
    }

    /// Copy environment truth onto the instrument fields. Does not read those fields back.
    private static func projectEnvironmentTruth(state: inout SimulationState) {
        state.twd.value = state.environmentTruth.trueWindDirection
        state.tws.value = state.environmentTruth.trueWindSpeedKnots
        state.seaTemp.value = state.environmentTruth.seaTemperatureCelsius
        state.airTemp.value = state.environmentTruth.airTemperatureCelsius
        state.humidity.value = state.environmentTruth.relativeHumidityPercent
        state.barometer.value = state.environmentTruth.airPressureHectopascals
        state.depth.value = state.environmentTruth.depthMeters
    }

    static func scheduledSentenceTypes(
        state: inout SimulationState,
        at timestamp: Date,
        snapshot: SimulationSnapshot,
        config: SimulationConfig
    ) -> [NMEASentenceType] {
        activeSentenceTypes(snapshot: snapshot, config: config).filter { type in
            let minimumInterval = effectiveInterval(for: type, config: config)
            guard minimumInterval > 0 else {
                state.lastEmissionDates[type] = timestamp
                return true
            }

            guard let lastEmission = state.lastEmissionDates[type] else {
                state.lastEmissionDates[type] = timestamp
                return true
            }

            let isDue = timestamp.timeIntervalSince(lastEmission) >= minimumInterval
            if isDue {
                state.lastEmissionDates[type] = timestamp
            }
            return isDue
        }
    }

    static func activeSentenceTypes(
        snapshot: SimulationSnapshot,
        config: SimulationConfig
    ) -> [NMEASentenceType] {
        var types: [NMEASentenceType] = []

        if config.sensorToggles.hasAnemometer && config.sentenceToggles.shouldSendMWV {
            types.append(.mwv)
        }
        if canSendFullWindData(config: config) && config.sentenceToggles.shouldSendMWD {
            types.append(.mwd)
        }
        if canSendFullWindData(config: config) && config.sentenceToggles.shouldSendVPW {
            types.append(.vpw)
        }

        if config.sensorToggles.hasCompass && config.sentenceToggles.shouldSendHDG {
            types.append(.hdg)
        }
        if config.sensorToggles.hasGyro && config.sentenceToggles.shouldSendHDT {
            types.append(.hdt)
        }
        if config.sensorToggles.hasGyro && config.sentenceToggles.shouldSendROT {
            types.append(.rot)
        }

        if config.sensorToggles.hasEchoSounder && config.sentenceToggles.shouldSendDBT {
            types.append(.dbt)
        }
        if config.sensorToggles.hasEchoSounder && abs(config.depthOffsetMeters) <= 99 && config.sentenceToggles.shouldSendDPT {
            types.append(.dpt)
        }
        if config.sensorToggles.hasWaterTempSensor && config.sentenceToggles.shouldSendMTW {
            types.append(.mtw)
        }
        if config.sensorToggles.hasSpeedLog && (config.sensorToggles.hasCompass || config.sensorToggles.hasGyro) && config.sentenceToggles.shouldSendVHW {
            types.append(.vhw)
        }
        if (config.sensorToggles.hasSpeedLog || config.sensorToggles.hasGPS) && config.sentenceToggles.shouldSendVBW {
            types.append(.vbw)
        }
        if config.sensorToggles.hasSpeedLog && config.sentenceToggles.shouldSendVLW {
            types.append(.vlw)
        }

        if config.sensorToggles.hasGPS {
            if config.sentenceToggles.shouldSendRMC { types.append(.rmc) }
            if config.sentenceToggles.shouldSendGGA { types.append(.gga) }
            if config.sentenceToggles.shouldSendVTG { types.append(.vtg) }
            if config.sentenceToggles.shouldSendGLL { types.append(.gll) }
            if config.sentenceToggles.shouldSendGSA { types.append(.gsa) }
            if config.sentenceToggles.shouldSendGSV { types.append(.gsv) }
            if config.sentenceToggles.shouldSendZDA { types.append(.zda) }

            if config.waypointNavigation.isActive {
                if config.sentenceToggles.shouldSendRMB { types.append(.rmb) }
                if config.sentenceToggles.shouldSendXTE { types.append(.xte) }
            }
        }

        return types
    }

    static func canSendFullWindData(config: SimulationConfig) -> Bool {
        let hasAnemometer = config.sensorToggles.hasAnemometer
        let hasBoatSpeed = config.sensorToggles.hasSpeedLog || config.sensorToggles.hasGPS
        let hasTrueHeading = config.sensorToggles.hasGyro || config.sensorToggles.hasCompass
        return hasAnemometer && hasBoatSpeed && hasTrueHeading
    }

    // MARK: - Pending transmissions

    static func flushPendingTransmissions(
        state: inout SimulationState,
        at timestamp: Date
    ) -> [PendingTransmission] {
        let due = state.pendingTransmissions.filter { $0.dueDate <= timestamp }
        state.pendingTransmissions.removeAll { $0.dueDate <= timestamp }
        return due
    }

    // MARK: - Steering & heading

    static func resolvedSteeringTrueHeading(
        state: SimulationState,
        config: SimulationConfig,
        variation: Double
    ) -> Double {
        _ = config
        _ = variation
        return normalizeAngle(state.vesselTruth.trueHeading)
    }

    static func computedTurnRate(
        currentHeading: Double,
        deltaTime: TimeInterval,
        previousReference: inout Double?
    ) -> Double {
        defer {
            previousReference = currentHeading
        }

        guard deltaTime > 0, let prev = previousReference else {
            return 0
        }

        let delta = calculateShortestRotation(from: prev, to: currentHeading)
        return delta / deltaTime * 60
    }

    // MARK: - Boat speed estimation

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

    private static func applyDrivenManeuverHeading(
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

    private static func hiddenTargetSpeedKnots(
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

    private static func respondedSpeed(
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

    private static func maneuverRetention(
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

    private static func applyDuePerformanceChanges(state: inout SimulationState, at timestamp: Date) {
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

    private static func updateManeuverPhase(
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

    // MARK: - Live weather noise

    static func syncLiveWeatherWindNoiseBaselineIfNeeded(
        state: inout SimulationState,
        fetchedAt: Date
    ) {
        if state.liveWeatherNoiseBaselineFetchDate != fetchedAt {
            state.liveWeatherNoiseBaselineFetchDate = fetchedAt
            state.liveWeatherWindSpeedOffsetKt = 0
            state.liveWeatherWindDirectionOffsetDeg = 0
        }
    }

    /// Smooth, mean-reverting variation around the forecast (Ornstein-Uhlenbeck process).
    static func evolveLiveWeatherWindNoise(
        state: inout SimulationState,
        deltaTime: TimeInterval
    ) {
        let dt = min(max(deltaTime, 0), 4)
        guard dt > 0 else { return }

        let zSpeed = unitGaussianRandom()
        let zDir = unitGaussianRandom()

        let thetaSpeed = 0.07
        let sigmaSpeedKt = 0.017
        state.liveWeatherWindSpeedOffsetKt += -thetaSpeed * state.liveWeatherWindSpeedOffsetKt * dt + sigmaSpeedKt * sqrt(dt) * zSpeed
        state.liveWeatherWindSpeedOffsetKt = state.liveWeatherWindSpeedOffsetKt.clamped(to: -1.1...1.1)

        let thetaDir = 0.06
        let sigmaDirDeg = 0.22
        state.liveWeatherWindDirectionOffsetDeg += -thetaDir * state.liveWeatherWindDirectionOffsetDeg * dt + sigmaDirDeg * sqrt(dt) * zDir
        state.liveWeatherWindDirectionOffsetDeg = state.liveWeatherWindDirectionOffsetDeg.clamped(to: -10...10)
    }

    // MARK: - Pure environment models

    static func simulatedMagneticVariation(for gpsData: GPSData, at timestamp: Date) -> Double {
        let seasonalCycle = sin(timestamp.timeIntervalSinceReferenceDate / 86_400 / 45) * 1.8
        let geographicTrend = gpsData.longitude * 0.16 + sin(toRadians(gpsData.latitude)) * 6.5
        return max(-25, min(25, geographicTrend + seasonalCycle))
    }

    static func simulatedCompassDeviation(heading: Double?) -> Double {
        guard let heading else {
            return 0
        }
        return sin(toRadians(heading * 1.7)) * 1.2
    }

    static func simulatedMovement(
        waterSpeed: Double,
        trueHeading: Double,
        at timestamp: Date,
        gpsData: GPSData
    ) -> (speedOverGround: Double, courseOverGround: Double) {
        let headingRadians = toRadians(trueHeading)
        let waterEast = waterSpeed * sin(headingRadians)
        let waterNorth = waterSpeed * cos(headingRadians)

        let current = simulatedCurrent(at: timestamp, gpsData: gpsData)
        let east = waterEast + current.eastKnots
        let north = waterNorth + current.northKnots

        let sog = sqrt(east * east + north * north)
        let cog = normalizeAngle(toDegrees(atan2(east, north)))
        return (sog, cog)
    }

    static func simulatedCurrent(at timestamp: Date, gpsData: GPSData) -> (eastKnots: Double, northKnots: Double) {
        // Keep COG aligned with heading until current/drift is exposed as an explicit operator control.
        _ = timestamp
        _ = gpsData
        return (eastKnots: 0, northKnots: 0)
    }

    static func simulatedGPSSignal(for gpsData: GPSData, at timestamp: Date) -> GPSSignalSnapshot {
        let timeComponent = timestamp.timeIntervalSinceReferenceDate / 90
        let latitudeComponent = sin(toRadians(gpsData.latitude))
        let longitudeComponent = cos(toRadians(gpsData.longitude))
        let visibleCount = max(8, min(12, 10 + Int(round(latitudeComponent * 1.4 + longitudeComponent * 1.2 + sin(timeComponent) * 1.1))))
        let usedCount = max(6, min(visibleCount, visibleCount - 1))
        let hdop = max(0.7, min(2.4, 1.9 - Double(usedCount - 6) * 0.18 + abs(sin(timeComponent)) * 0.25))
        let vdop = hdop + 0.4 + abs(cos(timeComponent)) * 0.18
        let pdop = sqrt(hdop * hdop + vdop * vdop)
        let altitudeMeters = 3.5 + sin(toRadians(gpsData.latitude * 3)) * 1.1 + cos(timeComponent / 2) * 0.6
        let geoidalSeparationMeters = 31 + sin(toRadians(gpsData.longitude * 2)) * 4

        return GPSSignalSnapshot(
            fixQuality: 1,
            fixMode: 3,
            selectionMode: "A",
            satellitesUsed: usedCount,
            hdop: hdop,
            vdop: vdop,
            pdop: pdop,
            altitudeMeters: altitudeMeters,
            geoidalSeparationMeters: geoidalSeparationMeters,
            satellites: simulatedSatellites(visibleCount: visibleCount, usedCount: usedCount, at: timestamp)
        )
    }

    static func simulatedSatellites(visibleCount: Int, usedCount: Int, at timestamp: Date) -> [GPSSatelliteSnapshot] {
        let prnPool = [3, 5, 7, 9, 11, 13, 15, 18, 21, 24, 27, 30, 32, 36, 38]
        let phase = timestamp.timeIntervalSinceReferenceDate / 60

        return (0..<visibleCount).map { index in
            let azimuth = Int(normalizeAngle(Double(index) * (360.0 / Double(visibleCount)) + phase * 7))
            let elevation = max(8, min(78, Int(round(22 + sin(phase + Double(index) * 0.7) * 18 + Double(index % 3) * 9))))
            let snrBase = 28 + Int(round(cos(phase / 2 + Double(index) * 0.9) * 8))
            let snr = max(22, min(48, snrBase + max(0, elevation - 20) / 8))

            return GPSSatelliteSnapshot(
                prn: prnPool[index % prnPool.count],
                elevation: elevation,
                azimuth: azimuth,
                snr: snr,
                isUsedInFix: index < usedCount
            )
        }
    }

    // MARK: - Helpers

    private static func resolvedDeltaTime(state: SimulationState, for timestamp: Date) -> TimeInterval {
        if let lastTick = state.lastSimulationTickDate {
            return max(0, timestamp.timeIntervalSince(lastTick))
        }
        return 0
    }
}
