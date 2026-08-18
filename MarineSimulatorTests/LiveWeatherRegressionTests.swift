import Foundation
import Testing
@testable import MarineSimulator

/// Locks live-weather fetch / apply / refresh after the `NMEASimulator+LiveWeather` extract.
@Suite(.serialized)
struct LiveWeatherRegressionTests {

    @Test
    func applyResolvedLiveWeatherValuesHonorsSensorToggles() {
        let simulator = makeLiveWeatherSimulator()
        simulator.weatherSourceMode = .liveWeather
        simulator.latestLiveWeather = makeLiveWeatherSnapshot()
        simulator.sensorToggles.hasAnemometer = false
        simulator.sensorToggles.hasWaterTempSensor = true
        simulator.sensorToggles.hasAirTempSensor = false
        simulator.sensorToggles.hasHumidtySensor = false
        simulator.sensorToggles.hasBarometer = false

        simulator.applyResolvedLiveWeatherValues()

        #expect(simulator.twd.value == nil)
        #expect(simulator.tws.value == nil)
        #expect(simulator.seaTemp.value == 16.4)
        #expect(simulator.airTemp.value == nil)
        #expect(simulator.humidity.value == nil)
        #expect(simulator.barometer.value == nil)
    }

    @Test
    func applyResolvedLiveWeatherValuesNoopsInManualMode() {
        let simulator = makeLiveWeatherSimulator()
        simulator.weatherSourceMode = .manual
        simulator.twd.value = 90
        simulator.latestLiveWeather = makeLiveWeatherSnapshot()

        simulator.applyResolvedLiveWeatherValues()

        #expect(simulator.twd.value == 90)
        #expect(simulator.activeLiveWeather == nil)
    }

    @Test
    func shouldRefreshWhenMissingSnapshotIntervalOrDistance() {
        let simulator = makeLiveWeatherSimulator()
        simulator.weatherSourceMode = .liveWeather
        simulator.liveWeatherSettings.refreshIntervalMinutes = 5
        simulator.liveWeatherSettings.minimumRefreshDistanceNM = 5

        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(simulator.shouldRefreshLiveWeather(at: fetchedAt))

        simulator.latestLiveWeather = makeLiveWeatherSnapshot(fetchedAt: fetchedAt)
        #expect(simulator.shouldRefreshLiveWeather(at: fetchedAt.addingTimeInterval(60)) == false)
        #expect(simulator.shouldRefreshLiveWeather(at: fetchedAt.addingTimeInterval(5 * 60)))

        simulator.gpsData.latitude = 43.19542 + 0.1
        #expect(simulator.shouldRefreshLiveWeather(at: fetchedAt.addingTimeInterval(60)))
    }

    @Test
    func shouldNotRefreshInManualMode() {
        let simulator = makeLiveWeatherSimulator()
        simulator.weatherSourceMode = .manual
        #expect(simulator.shouldRefreshLiveWeather(at: Date()) == false)
    }

    @Test
    func generateLiveWeatherValueNilBaseClampsAndWraps() {
        let simulator = makeLiveWeatherSimulator()

        #expect(simulator.generateLiveWeatherValue(base: nil, jitter: 0, range: 0...10, wraps: false) == nil)
        #expect(simulator.generateLiveWeatherValue(base: 5, jitter: 0, range: 0...10, wraps: false) == 5)
        #expect(simulator.generateLiveWeatherValue(base: 15, jitter: 0, range: 0...10, wraps: false) == 10)
        #expect(simulator.generateLiveWeatherValue(base: 370, jitter: 0, range: 0...359, wraps: true) == 10)
    }

    @Test
    func refreshWithoutGPSFails() async {
        let simulator = makeLiveWeatherSimulator()
        simulator.sensorToggles.hasGPS = false
        simulator.weatherSourceMode = .liveWeather

        let succeeded = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(succeeded == false)
        #expect(simulator.liveWeatherStatus.state == .failed)
        #expect(simulator.liveWeatherStatus.message.contains("Enable GPS"))
        #expect(simulator.latestLiveWeather == nil)
    }

    @Test
    func startWithoutCachedWeatherDoesNotTransmitUntilFetchCompletes() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedLiveWeatherDefaults(),
            weatherService: DelayedStubLiveWeatherService(
                snapshot: makeLiveWeatherSnapshot(),
                delayNanoseconds: 80_000_000
            )
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather
        #expect(simulator.latestLiveWeather == nil)

        simulator.startSimulation()
        #expect(simulator.isTransmitting == false)

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, !simulator.isTransmitting {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(simulator.isTransmitting)
        #expect(simulator.latestLiveWeather?.trueWindDirection == 145)
        simulator.stopSimulation()
    }

    @Test
    func failedStartWithoutCacheDoesNotTransmit() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedLiveWeatherDefaults(),
            weatherService: FailingLiveWeatherService()
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather

        simulator.startSimulation()
        try? await Task.sleep(nanoseconds: 120_000_000)

        #expect(simulator.isTransmitting == false)
        #expect(simulator.latestLiveWeather == nil)
        #expect(simulator.transportHistory.contains(where: { $0.message.contains("live weather unavailable") }))
    }

    @Test
    func switchingToManualResetsNoiseAndStatus() {
        let simulator = makeLiveWeatherSimulator()
        simulator.liveWeatherWindSpeedOffsetKt = 0.8
        simulator.liveWeatherWindDirectionOffsetDeg = 4
        simulator.liveWeatherNoiseBaselineFetchDate = Date()
        simulator.weatherSourceMode = .liveWeather
        simulator.weatherSourceMode = .manual

        #expect(simulator.liveWeatherStatus == .idle)
        #expect(simulator.liveWeatherWindSpeedOffsetKt == 0)
        #expect(simulator.liveWeatherWindDirectionOffsetDeg == 0)
        #expect(simulator.liveWeatherNoiseBaselineFetchDate == nil)
    }

    @Test
    func triggerRefreshSkipsWhenAFetchIsAlreadyRunning() {
        let simulator = makeLiveWeatherSimulator()
        simulator.weatherSourceMode = .liveWeather
        simulator.liveWeatherTask?.cancel()
        simulator.liveWeatherTask = Task { true }
        simulator.liveWeatherStatus = .idle
        defer { simulator.liveWeatherTask?.cancel(); simulator.liveWeatherTask = nil }

        simulator.triggerLiveWeatherRefreshIfNeeded(at: Date())

        #expect(simulator.latestLiveWeather == nil)
        #expect(simulator.liveWeatherStatus == .idle)
    }
}

private func makeLiveWeatherSimulator() -> NMEASimulator {
    NMEASimulator(
        userDefaults: isolatedLiveWeatherDefaults(),
        weatherService: PendingLiveWeatherService()
    )
}

private func isolatedLiveWeatherDefaults() -> UserDefaults {
    let suiteName = "MarineSimulatorTests.LiveWeather.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeLiveWeatherSnapshot(fetchedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> LiveWeatherSnapshot {
    LiveWeatherSnapshot(
        fetchedAt: fetchedAt,
        latitude: 43.19542,
        longitude: 27.89615,
        trueWindDirection: 145,
        trueWindSpeedKnots: 18,
        windGustSpeedKnots: 22,
        seaSurfaceTemperatureCelsius: 16.4,
        airTemperatureCelsius: 21.3,
        relativeHumidityPercent: 68,
        airPressureHectopascals: 1014.2,
        sourceName: "Stub",
        marineSourceName: "Stub Marine"
    )
}

private struct StubLiveWeatherService: WeatherService {
    let snapshot: LiveWeatherSnapshot

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        LiveWeatherSnapshot(
            fetchedAt: date,
            latitude: latitude,
            longitude: longitude,
            trueWindDirection: snapshot.trueWindDirection,
            trueWindSpeedKnots: snapshot.trueWindSpeedKnots,
            windGustSpeedKnots: snapshot.windGustSpeedKnots,
            seaSurfaceTemperatureCelsius: snapshot.seaSurfaceTemperatureCelsius,
            airTemperatureCelsius: snapshot.airTemperatureCelsius,
            relativeHumidityPercent: snapshot.relativeHumidityPercent,
            airPressureHectopascals: snapshot.airPressureHectopascals,
            sourceName: snapshot.sourceName,
            marineSourceName: snapshot.marineSourceName
        )
    }
}

private struct DelayedStubLiveWeatherService: WeatherService {
    let snapshot: LiveWeatherSnapshot
    let delayNanoseconds: UInt64

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await StubLiveWeatherService(snapshot: snapshot).fetchWeather(
            latitude: latitude,
            longitude: longitude,
            date: date
        )
    }
}

private struct FailingLiveWeatherService: WeatherService {
    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        throw WeatherServiceError.requestTimedOut
    }
}

private struct PendingLiveWeatherService: WeatherService {
    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw WeatherServiceError.requestTimedOut
    }
}
