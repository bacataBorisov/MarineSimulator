import Foundation
import CoreLocation

extension NMEASimulator {

    // MARK: - Live weather

    func startSimulationWithFreshLiveWeather() {
        let startupDate = Date.now

        liveWeatherTask?.cancel()
        liveWeatherTask = Task { [weak self] in
            guard let self else { return false }
            defer { self.liveWeatherTask = nil }

            let success = await self.refreshLiveWeatherNow(force: true, at: startupDate)
            guard success || self.latestLiveWeather != nil else {
                self.appendHistoryEvent(level: .warning, category: .lifecycle, message: "Simulation start cancelled: live weather unavailable")
                return false
            }

            self.beginSimulationRun()
            return true
        }
    }

    func refreshLiveWeather(force: Bool = false) {
        if force, let liveWeatherTask {
            liveWeatherTask.cancel()
            self.liveWeatherTask = nil
        } else if liveWeatherTask != nil {
            return
        }

        liveWeatherTask = Task { [weak self] in
            guard let self else { return false }
            defer { self.liveWeatherTask = nil }
            return await self.refreshLiveWeatherNow(force: force)
        }
    }

    @discardableResult
    func refreshLiveWeatherNow(force: Bool = false, at timestamp: Date = .now) async -> Bool {
        guard weatherSourceMode == .liveWeather else {
            liveWeatherStatus = .idle
            return false
        }

        guard sensorToggles.hasGPS else {
            liveWeatherStatus = LiveWeatherStatus(state: .failed, message: "Enable GPS to use live weather.", lastUpdated: latestLiveWeather?.fetchedAt)
            return false
        }

        if !force, !shouldRefreshLiveWeather(at: timestamp) {
            return false
        }

        liveWeatherStatus = LiveWeatherStatus(state: .fetching, message: "Fetching live weather…", lastUpdated: latestLiveWeather?.fetchedAt)

        do {
            let snapshot = try await weatherService.fetchWeather(
                latitude: gpsData.latitude,
                longitude: gpsData.longitude,
                date: timestamp
            )
            guard !Task.isCancelled, weatherSourceMode == .liveWeather else {
                liveWeatherStatus = .idle
                return false
            }
            latestLiveWeather = snapshot
            applyResolvedLiveWeatherValues()
            liveWeatherStatus = LiveWeatherStatus(
                state: .ready,
                message: "Live weather updated from \(snapshot.sourceName).",
                lastUpdated: snapshot.fetchedAt
            )
            return true
        } catch {
            guard !Task.isCancelled, weatherSourceMode == .liveWeather else {
                liveWeatherStatus = .idle
                return false
            }
            liveWeatherStatus = LiveWeatherStatus(
                state: .failed,
                message: latestLiveWeather == nil
                    ? error.localizedDescription
                    : "Live weather refresh failed. Using last good weather. \(error.localizedDescription)",
                lastUpdated: latestLiveWeather?.fetchedAt
            )
            return false
        }
    }

    var activeLiveWeather: LiveWeatherSnapshot? {
        guard weatherSourceMode == .liveWeather else {
            return nil
        }
        return latestLiveWeather
    }

    func triggerLiveWeatherRefreshIfNeeded(at timestamp: Date) {
        guard weatherSourceMode == .liveWeather else {
            return
        }

        guard liveWeatherTask == nil, shouldRefreshLiveWeather(at: timestamp) else {
            return
        }

        refreshLiveWeather(force: false)
    }

    func shouldRefreshLiveWeather(at timestamp: Date) -> Bool {
        guard weatherSourceMode == .liveWeather else {
            return false
        }

        guard let latestLiveWeather else {
            return true
        }

        if timestamp.timeIntervalSince(latestLiveWeather.fetchedAt) >= liveWeatherSettings.refreshInterval {
            return true
        }

        let latestLocation = CLLocation(latitude: latestLiveWeather.latitude, longitude: latestLiveWeather.longitude)
        let currentLocation = CLLocation(latitude: gpsData.latitude, longitude: gpsData.longitude)
        let distanceNM = currentLocation.distance(from: latestLocation) / 1852
        return distanceNM >= liveWeatherSettings.minimumRefreshDistanceNM
    }

    func resetLiveWeatherWindNoiseState() {
        liveWeatherWindSpeedOffsetKt = 0
        liveWeatherWindDirectionOffsetDeg = 0
        liveWeatherNoiseBaselineFetchDate = nil
    }

    func generateLiveWeatherValue(
        base: Double?,
        jitter: Double,
        range: ClosedRange<Double>,
        wraps: Bool
    ) -> Double? {
        guard let base else {
            return nil
        }

        let offset = Double.random(in: -jitter...jitter)
        if wraps {
            return normalizeAngle(base + offset)
        }

        return (base + offset).clamped(to: range)
    }

    func applyResolvedLiveWeatherValues() {
        guard let liveWeather = activeLiveWeather else {
            return
        }

        twd.value = sensorToggles.hasAnemometer
            ? liveWeather.trueWindDirection
            : nil
        tws.value = sensorToggles.hasAnemometer
            ? liveWeather.trueWindSpeedKnots
            : nil
        seaTemp.value = sensorToggles.hasWaterTempSensor
            ? liveWeather.seaSurfaceTemperatureCelsius
            : nil
        airTemp.value = sensorToggles.hasAirTempSensor
            ? liveWeather.airTemperatureCelsius
            : nil
        humidity.value = sensorToggles.hasHumidtySensor
            ? liveWeather.relativeHumidityPercent
            : nil
        barometer.value = sensorToggles.hasBarometer
            ? liveWeather.airPressureHectopascals
            : nil
    }
}
