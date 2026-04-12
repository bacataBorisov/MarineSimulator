import Foundation

protocol WeatherService {
    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot
}

enum WeatherServiceError: LocalizedError {
    case invalidResponse
    case noWindData
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Weather provider returned an invalid response."
        case .noWindData:
            return "Weather provider returned no usable wind data."
        case .requestTimedOut:
            return "Live weather request timed out."
        }
    }
}

struct OpenMeteoWeatherService: WeatherService {
    private let session: URLSession
    private let forecastBaseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let marineBaseURL = URL(string: "https://marine-api.open-meteo.com/v1/marine")!
    private let maximumAttempts = 2

    init(session: URLSession = OpenMeteoWeatherService.makeDefaultSession()) {
        self.session = session
    }

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        async let forecastResponse = fetchForecast(latitude: latitude, longitude: longitude)
        async let marineResponse = fetchMarineIfAvailable(latitude: latitude, longitude: longitude)

        let forecast = try await forecastResponse
        let marine = await marineResponse

        let seaSurfaceTemperature = marine?.current?.seaSurfaceTemperature
            ?? marine?.hourly?.valueNearest(to: date)

        return LiveWeatherSnapshot(
            fetchedAt: date,
            latitude: latitude,
            longitude: longitude,
            trueWindDirection: forecast.current.windDirection10m,
            trueWindSpeedKnots: forecast.current.windSpeed10m,
            windGustSpeedKnots: nil,
            seaSurfaceTemperatureCelsius: seaSurfaceTemperature,
            airTemperatureCelsius: nil,
            relativeHumidityPercent: nil,
            airPressureHectopascals: nil,
            sourceName: "Open-Meteo",
            marineSourceName: seaSurfaceTemperature == nil ? nil : "Open-Meteo Marine"
        )
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        var components = URLComponents(url: forecastBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "cell_selection", value: "sea")
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidResponse
        }

        let (data, response) = try await load(request: URLRequest(url: url))
        try validate(response: response)

        let decoded = try JSONDecoder.weatherDecoder.decode(ForecastResponse.self, from: data)
        guard decoded.current.windSpeed10m != nil || decoded.current.windDirection10m != nil else {
            throw WeatherServiceError.noWindData
        }

        return decoded
    }

    private func fetchMarineIfAvailable(latitude: Double, longitude: Double) async -> MarineResponse? {
        do {
            return try await fetchMarine(latitude: latitude, longitude: longitude)
        } catch {
            return nil
        }
    }

    private func fetchMarine(latitude: Double, longitude: Double) async throws -> MarineResponse {
        var components = URLComponents(url: marineBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "sea_surface_temperature"),
            URLQueryItem(name: "hourly", value: "sea_surface_temperature"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "cell_selection", value: "sea")
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidResponse
        }

        let (data, response) = try await load(request: URLRequest(url: url))
        try validate(response: response)
        return try JSONDecoder.weatherDecoder.decode(MarineResponse.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw WeatherServiceError.invalidResponse
        }
    }

    fileprivate func load(request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 1

        while true {
            do {
                return try await session.data(for: request)
            } catch {
                let mappedError = error.asWeatherServiceError
                guard attempt < maximumAttempts, mappedError.isTimeoutError else {
                    throw mappedError
                }
                attempt += 1
            }
        }
    }

    fileprivate static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

struct GlobalFallbackWeatherService: WeatherService {
    private let atmospheric: any WeatherService
    private let marineTemperature: (any WeatherService)?

    init(
        atmospheric: any WeatherService = METNorwayWeatherService(),
        marineTemperature: (any WeatherService)? = OpenMeteoMarineTemperatureService()
    ) {
        self.atmospheric = atmospheric
        self.marineTemperature = marineTemperature
    }

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        var atmosphericSnapshot = try await atmospheric.fetchWeather(latitude: latitude, longitude: longitude, date: date)

        guard let marineTemperature else {
            return atmosphericSnapshot
        }

        guard let marineSnapshot = try? await marineTemperature.fetchWeather(latitude: latitude, longitude: longitude, date: date),
              marineSnapshot.seaSurfaceTemperatureCelsius != nil else {
            return atmosphericSnapshot
        }

        atmosphericSnapshot = LiveWeatherSnapshot(
            fetchedAt: atmosphericSnapshot.fetchedAt,
            latitude: atmosphericSnapshot.latitude,
            longitude: atmosphericSnapshot.longitude,
            trueWindDirection: atmosphericSnapshot.trueWindDirection,
            trueWindSpeedKnots: atmosphericSnapshot.trueWindSpeedKnots,
            windGustSpeedKnots: atmosphericSnapshot.windGustSpeedKnots,
            seaSurfaceTemperatureCelsius: marineSnapshot.seaSurfaceTemperatureCelsius,
            airTemperatureCelsius: atmosphericSnapshot.airTemperatureCelsius,
            relativeHumidityPercent: atmosphericSnapshot.relativeHumidityPercent,
            airPressureHectopascals: atmosphericSnapshot.airPressureHectopascals,
            sourceName: atmosphericSnapshot.sourceName,
            marineSourceName: marineSnapshot.marineSourceName ?? marineSnapshot.sourceName
        )

        return atmosphericSnapshot
    }
}

struct OpenMeteoMarineTemperatureService: WeatherService {
    private let session: URLSession
    private let marineBaseURL = URL(string: "https://marine-api.open-meteo.com/v1/marine")!

    init(session: URLSession = OpenMeteoWeatherService.makeDefaultSession()) {
        self.session = session
    }

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        let marine = try await fetchMarine(latitude: latitude, longitude: longitude)
        let seaSurfaceTemperature = marine.current?.seaSurfaceTemperature
            ?? marine.hourly?.valueNearest(to: date)

        return LiveWeatherSnapshot(
            fetchedAt: date,
            latitude: latitude,
            longitude: longitude,
            trueWindDirection: nil,
            trueWindSpeedKnots: nil,
            windGustSpeedKnots: nil,
            seaSurfaceTemperatureCelsius: seaSurfaceTemperature,
            airTemperatureCelsius: nil,
            relativeHumidityPercent: nil,
            airPressureHectopascals: nil,
            sourceName: "Open-Meteo Marine",
            marineSourceName: seaSurfaceTemperature == nil ? nil : "Open-Meteo Marine"
        )
    }

    private func fetchMarine(latitude: Double, longitude: Double) async throws -> MarineResponse {
        var components = URLComponents(url: marineBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "sea_surface_temperature"),
            URLQueryItem(name: "hourly", value: "sea_surface_temperature"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "cell_selection", value: "sea")
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidResponse
        }

        let (data, response) = try await load(request: URLRequest(url: url))
        try validate(response: response)
        return try JSONDecoder.weatherDecoder.decode(MarineResponse.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw WeatherServiceError.invalidResponse
        }
    }

    private func load(request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 1

        while true {
            do {
                return try await session.data(for: request)
            } catch {
                let mappedError = error.asWeatherServiceError
                guard attempt < 2, mappedError.isTimeoutError else {
                    throw mappedError
                }
                attempt += 1
            }
        }
    }
}

struct METNorwayWeatherService: WeatherService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")!
    private let userAgent = "MarineSimulator/1.0 github.com/bacataborisov/MarineSimulator"

    init(session: URLSession = OpenMeteoWeatherService.makeDefaultSession()) {
        self.session = session
    }

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude))
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await load(request: request)
        try validate(response: response)

        let forecast = try JSONDecoder.weatherDecoder.decode(METNorwayResponse.self, from: data)
        guard let details = forecast.nearestTimeseries(to: date)?.data.instant.details else {
            throw WeatherServiceError.noWindData
        }

        let windSpeedKnots = details.windSpeed.map { $0 * UnitConversion.metersPerSecondToKnots }
        let windGustKnots = details.windGustSpeed.map { $0 * UnitConversion.metersPerSecondToKnots }
        guard windSpeedKnots != nil || details.windFromDirection != nil else {
            throw WeatherServiceError.noWindData
        }

        return LiveWeatherSnapshot(
            fetchedAt: date,
            latitude: latitude,
            longitude: longitude,
            trueWindDirection: details.windFromDirection,
            trueWindSpeedKnots: windSpeedKnots,
            windGustSpeedKnots: windGustKnots,
            seaSurfaceTemperatureCelsius: nil,
            airTemperatureCelsius: details.airTemperature,
            relativeHumidityPercent: details.relativeHumidity,
            airPressureHectopascals: details.airPressureAtSeaLevel,
            sourceName: "MET Norway",
            marineSourceName: nil
        )
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw WeatherServiceError.invalidResponse
        }
    }

    private func load(request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 1

        while true {
            do {
                return try await session.data(for: request)
            } catch {
                let mappedError = error.asWeatherServiceError
                guard attempt < 2, mappedError.isTimeoutError else {
                    throw mappedError
                }
                attempt += 1
            }
        }
    }
}

private struct ForecastResponse: Decodable {
    let current: CurrentForecast

    struct CurrentForecast: Decodable {
        let windSpeed10m: Double?
        let windDirection10m: Double?

        private enum CodingKeys: String, CodingKey {
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
        }
    }
}

private struct MarineResponse: Decodable {
    let current: MarineCurrent?
    let hourly: MarineHourly?
}

private struct METNorwayResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let timeseries: [Timeseries]
    }

    struct Timeseries: Decodable {
        let time: Date
        let data: DataBlock
    }

    struct DataBlock: Decodable {
        let instant: InstantBlock
    }

    struct InstantBlock: Decodable {
        let details: Details
    }

    struct Details: Decodable {
        let windSpeed: Double?
        let windGustSpeed: Double?
        let windFromDirection: Double?
        let airTemperature: Double?
        let relativeHumidity: Double?
        let airPressureAtSeaLevel: Double?

        private enum CodingKeys: String, CodingKey {
            case windSpeed = "wind_speed"
            case windGustSpeed = "wind_speed_of_gust"
            case windFromDirection = "wind_from_direction"
            case airTemperature = "air_temperature"
            case relativeHumidity = "relative_humidity"
            case airPressureAtSeaLevel = "air_pressure_at_sea_level"
        }
    }

    func nearestTimeseries(to date: Date) -> Timeseries? {
        properties.timeseries.min { lhs, rhs in
            abs(lhs.time.timeIntervalSince(date)) < abs(rhs.time.timeIntervalSince(date))
        }
    }
}

private struct MarineCurrent: Decodable {
    let seaSurfaceTemperature: Double?

    private enum CodingKeys: String, CodingKey {
        case seaSurfaceTemperature = "sea_surface_temperature"
    }
}

private struct MarineHourly: Decodable {
    let time: [Date]
    let seaSurfaceTemperature: [Double?]

    private enum CodingKeys: String, CodingKey {
        case time
        case seaSurfaceTemperature = "sea_surface_temperature"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode([Date].self, forKey: .time)

        let rawValues = try container.decodeIfPresent([Double].self, forKey: .seaSurfaceTemperature)
        if let rawValues {
            seaSurfaceTemperature = rawValues.map(Optional.some)
        } else {
            seaSurfaceTemperature = Array(repeating: nil, count: time.count)
        }
    }

    func valueNearest(to date: Date) -> Double? {
        guard !time.isEmpty, time.count == seaSurfaceTemperature.count else {
            return nil
        }

        let nearestIndex = time.enumerated().min { lhs, rhs in
            abs(lhs.element.timeIntervalSince(date)) < abs(rhs.element.timeIntervalSince(date))
        }?.offset

        guard let nearestIndex else {
            return nil
        }

        return seaSurfaceTemperature[nearestIndex]
    }
}

private extension JSONDecoder {
    static var weatherDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = Self.openMeteoDateFormatter.date(from: value) {
                return date
            }

            if let date = Self.openMeteoISO8601Formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected Open-Meteo timestamp.")
        }
        return decoder
    }

    private static let openMeteoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    private static let openMeteoISO8601Formatter = ISO8601DateFormatter()
}

private enum UnitConversion {
    static let metersPerSecondToKnots = 1.9438444924406
}

private extension Error {
    var asWeatherServiceError: Error {
        if let urlError = self as? URLError, urlError.code == .timedOut {
            return WeatherServiceError.requestTimedOut
        }

        return self
    }

    var isTimeoutError: Bool {
        if let weatherServiceError = self as? WeatherServiceError, weatherServiceError == .requestTimedOut {
            return true
        }
        if let urlError = self as? URLError, urlError.code == .timedOut {
            return true
        }
        return false
    }
}
