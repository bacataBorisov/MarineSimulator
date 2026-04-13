import Foundation

enum WeatherSourceMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case liveWeather

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .liveWeather:
            return "Live Weather"
        }
    }
}

struct LiveWeatherSettings: Codable, Equatable {
    /// Default 5 min: well within typical free-tier fair use (e.g. Open-Meteo, MET Norway) for one client.
    var refreshIntervalMinutes: Int = 5
    var minimumRefreshDistanceNM: Double = 5

    var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}

struct LiveWeatherSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double
    let trueWindDirection: Double?
    let trueWindSpeedKnots: Double?
    let windGustSpeedKnots: Double?
    let seaSurfaceTemperatureCelsius: Double?
    let airTemperatureCelsius: Double?
    let relativeHumidityPercent: Double?
    let airPressureHectopascals: Double?
    let sourceName: String
    let marineSourceName: String?
}

enum LiveWeatherStatusState: String, Equatable {
    case idle
    case fetching
    case ready
    case failed
}

struct LiveWeatherStatus: Equatable {
    var state: LiveWeatherStatusState
    var message: String
    var lastUpdated: Date?

    static let idle = LiveWeatherStatus(
        state: .idle,
        message: "Manual weather mode",
        lastUpdated: nil
    )
}
