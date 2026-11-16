import Foundation

extension SimulationEngine {

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
        gpsData: GPSData,
        currentProgram: ExperimentCurrentProgram = .none
    ) -> (speedOverGround: Double, courseOverGround: Double) {
        let headingRadians = toRadians(trueHeading)
        let waterEast = waterSpeed * sin(headingRadians)
        let waterNorth = waterSpeed * cos(headingRadians)

        let current = simulatedCurrent(at: timestamp, gpsData: gpsData, currentProgram: currentProgram)
        let east = waterEast + current.eastKnots
        let north = waterNorth + current.northKnots

        let sog = sqrt(east * east + north * north)
        let cog = normalizeAngle(toDegrees(atan2(east, north)))
        return (sog, cog)
    }

    static func simulatedCurrent(
        at timestamp: Date,
        gpsData: GPSData,
        currentProgram: ExperimentCurrentProgram = .none
    ) -> (eastKnots: Double, northKnots: Double) {
        _ = timestamp
        _ = gpsData
        let drift = currentProgram.driftKnots
        guard drift.isFinite, drift > 0 else {
            return (eastKnots: 0, northKnots: 0)
        }
        let setRadians = toRadians(currentProgram.setDegrees)
        return (
            eastKnots: drift * sin(setRadians),
            northKnots: drift * cos(setRadians)
        )
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

    static func resolvedDeltaTime(state: SimulationState, for timestamp: Date) -> TimeInterval {
        if let lastTick = state.lastSimulationTickDate {
            return max(0, timestamp.timeIntervalSince(lastTick))
        }
        return 0
    }
}
