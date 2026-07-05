import Foundation

/// Pure simulation logic that operates on `SimulationState` + `SimulationConfig`.
///
/// Every method is static and side-effect-free (apart from mutating the `inout` state).
/// `NMEASimulator` delegates here for both the main-thread single-shot path and the
/// off-main fast transmit loop, eliminating the duplicated method pairs.
enum SimulationEngine {

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
        let deltaTime = resolvedDeltaTime(state: state, for: timestamp)

        // --- Weather ---
        if config.weatherSourceMode == .liveWeather {
            if let liveWeather = config.latestLiveWeather {
                syncLiveWeatherWindNoiseBaselineIfNeeded(
                    state: &state,
                    fetchedAt: liveWeather.fetchedAt
                )
                evolveLiveWeatherWindNoise(state: &state, deltaTime: deltaTime)

                if config.sensorToggles.hasAnemometer, let baseDir = liveWeather.trueWindDirection {
                    state.twd.value = normalizeAngle(baseDir + state.liveWeatherWindDirectionOffsetDeg)
                } else {
                    state.twd.value = nil
                }
                if config.sensorToggles.hasAnemometer, let baseKt = liveWeather.trueWindSpeedKnots {
                    state.tws.value = (baseKt + state.liveWeatherWindSpeedOffsetKt)
                        .clamped(to: SimulatedValueType.windSpeed.defaultRange)
                } else {
                    state.tws.value = nil
                }
                state.seaTemp.value = config.sensorToggles.hasWaterTempSensor
                    ? liveWeatherValueGenerator(
                        liveWeather.seaSurfaceTemperatureCelsius,
                        0.3,
                        SimulatedValueType.seaTemp.defaultRange,
                        false
                    )
                    : nil
                state.airTemp.value = config.sensorToggles.hasAirTempSensor
                    ? liveWeatherValueGenerator(
                        liveWeather.airTemperatureCelsius,
                        0.4,
                        SimulatedValueType.airTemp.defaultRange,
                        false
                    )
                    : nil
                state.humidity.value = config.sensorToggles.hasHumidtySensor
                    ? liveWeatherValueGenerator(
                        liveWeather.relativeHumidityPercent,
                        1.8,
                        SimulatedValueType.humidity.defaultRange,
                        false
                    )
                    : nil
                state.barometer.value = config.sensorToggles.hasBarometer
                    ? liveWeatherValueGenerator(
                        liveWeather.airPressureHectopascals,
                        0.8,
                        SimulatedValueType.barometer.defaultRange,
                        false
                    )
                    : nil
            } else {
                state.twd.value = nil
                state.tws.value = nil
                state.seaTemp.value = nil
                state.airTemp.value = nil
                state.humidity.value = nil
                state.barometer.value = nil
            }
        } else {
            state.twd.value = state.twd.generateRandomValue(shouldGenerate: config.sensorToggles.hasAnemometer)
            state.tws.value = state.tws.generateRandomValue(shouldGenerate: config.sensorToggles.hasAnemometer)
            state.seaTemp.value = state.seaTemp.generateRandomValue(shouldGenerate: config.sensorToggles.hasWaterTempSensor)
            state.airTemp.value = state.airTemp.generateRandomValue(shouldGenerate: config.sensorToggles.hasAirTempSensor)
            state.humidity.value = state.humidity.generateRandomValue(shouldGenerate: config.sensorToggles.hasHumidtySensor)
            state.barometer.value = state.barometer.generateRandomValue(shouldGenerate: config.sensorToggles.hasBarometer)
        }

        // --- Heading ---
        // Magnetic heading is the primary random walk; gyro is synced to magnetic + variation
        // so the compass dial (which shows magnetic heading) stays aligned with the user's slider.
        if !config.tackAnimationInProgress {
            state.heading.value = state.heading.generateRandomValue(shouldGenerate: config.sensorToggles.hasCompass)
            if config.sensorToggles.hasGyro {
                let variation = simulatedMagneticVariation(for: state.gpsData, at: timestamp)
                let syncedTrue = normalizeAngle((state.heading.value ?? state.heading.centerValue) + variation)
                state.gyroHeading.value = syncedTrue
                state.gyroHeading.centerValue = syncedTrue.clamped(to: state.gyroHeading.range)
            }
        }
        state.depth.value = state.depth.generateRandomValue(shouldGenerate: config.sensorToggles.hasEchoSounder)

        // --- Speed & Movement ---
        let magneticVariation = simulatedMagneticVariation(for: state.gpsData, at: timestamp)
        let boatTrueHeading = resolvedSteeringTrueHeading(
            state: state,
            config: config,
            variation: magneticVariation
        )

        if config.boatSpeedMode == .estimated {
            state.speed.value = estimatedBoatSpeed(
                trueHeading: boatTrueHeading,
                state: state,
                config: config
            )
        } else {
            state.speed.value = state.speed.generateRandomValue(shouldGenerate: config.sensorToggles.hasSpeedLog)
        }

        let waterSpeed = state.speed.value ?? state.gpsData.speedOverGround
        let movement = simulatedMovement(
            waterSpeed: waterSpeed,
            trueHeading: boatTrueHeading,
            at: timestamp,
            gpsData: state.gpsData
        )

        if config.sensorToggles.hasGPS && deltaTime > 0 {
            state.gpsData.updatePosition(
                deltaTime: deltaTime,
                sog: movement.speedOverGround,
                cog: movement.courseOverGround
            )
        }

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
            navigationTarget: navTarget
        )

        state.latestSnapshot = snapshot
        state.lastSimulationTickDate = timestamp
        return snapshot
    }

    // MARK: - Scheduling

    static func shouldAdvanceSimulation(
        state: SimulationState,
        at timestamp: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let lastTick = state.lastSimulationTickDate else {
            return true
        }
        return timestamp.timeIntervalSince(lastTick) >= interval
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
        if config.sensorToggles.hasGyro {
            return normalizeAngle(state.gyroHeading.value ?? state.gyroHeading.centerValue)
        }

        if config.sensorToggles.hasCompass {
            return normalizeAngle((state.heading.value ?? state.heading.centerValue) + variation)
        }

        return normalizeAngle(state.gpsData.courseOverGround)
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

    static func estimatedBoatSpeed(
        trueHeading: Double,
        state: SimulationState,
        config: SimulationConfig
    ) -> Double? {
        guard config.sensorToggles.hasSpeedLog, let trueWindSpeed = state.tws.value else {
            return nil
        }

        let trueWindDirection = state.twd.value ?? state.gpsData.courseOverGround
        let trueWindAngle = abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))
        let baseSpeed = config.boatProfile.estimatedBoatSpeed(
            trueWindSpeedKnots: trueWindSpeed,
            trueWindAngleDegrees: trueWindAngle
        )

        let seaStatePenalty = config.weatherSourceMode == .liveWeather ? 0.96 : 1.0
        let variationPenalty = max(0.88, 1.0 - (state.speed.offset / 100))
        return (baseSpeed * seaStatePenalty * variationPenalty).clamped(to: SimulatedValueType.speedLog.defaultRange)
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
