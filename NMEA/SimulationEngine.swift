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
}
