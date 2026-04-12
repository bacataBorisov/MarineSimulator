import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct OpenMeteoWeatherServiceTests {
    @Test
    func fetchWeatherDecodesMarineHourlyTimestampsWithoutTimeZoneSuffix() async throws {
        let session = makeSession { request in
            guard let url = request.url else {
                throw StubTestError.missingURL
            }

            if url.host == "api.open-meteo.com" {
                return .ok(
                    """
                    {
                      "current": {
                        "wind_speed_10m": 18.2,
                        "wind_direction_10m": 146
                      }
                    }
                    """
                )
            }

            return .ok(
                """
                {
                  "hourly": {
                    "time": ["2026-04-10T12:00"],
                    "sea_surface_temperature": [16.4]
                  }
                }
                """
            )
        }
        let service = OpenMeteoWeatherService(session: session)

        let snapshot = try await service.fetchWeather(
            latitude: 43.19542,
            longitude: 27.89615,
            date: Date(timeIntervalSince1970: 1_775_822_400)
        )

        #expect(snapshot.trueWindDirection == 146)
        #expect(snapshot.trueWindSpeedKnots == 18.2)
        #expect(snapshot.seaSurfaceTemperatureCelsius == 16.4)
    }

    @Test
    func fetchWeatherRequestsSeaGridForForecastWind() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.append(request)
            guard let url = request.url else {
                throw StubTestError.missingURL
            }

            if url.host == "api.open-meteo.com" {
                return .ok(
                    """
                    {
                      "current": {
                        "wind_speed_10m": 12.5,
                        "wind_direction_10m": 90
                      }
                    }
                    """
                )
            }

            return .ok(
                """
                {
                  "current": {
                    "sea_surface_temperature": 15.1
                  }
                }
                """
            )
        }
        let service = OpenMeteoWeatherService(session: session)

        _ = try await service.fetchWeather(
            latitude: 43.19542,
            longitude: 27.89615,
            date: Date(timeIntervalSince1970: 1_775_822_400)
        )

        let forecastRequest = try #require(
            recorder.snapshot().first { $0.url?.host == "api.open-meteo.com" }
        )
        let forecastURL = try #require(forecastRequest.url)
        let components = try #require(
            URLComponents(url: forecastURL, resolvingAgainstBaseURL: false)
        )
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(items["current"] == "wind_speed_10m,wind_direction_10m")
        #expect(items["wind_speed_unit"] == "kn")
        #expect(items["timezone"] == "GMT")
        #expect(items["cell_selection"] == "sea")
    }

    @Test
    func metNorwayFallbackProvidesGlobalWindWhenOpenMeteoTimesOut() async throws {
        let sharedSession = makeSession { request in
            let url = try #require(request.url)
            switch url.host {
            case "api.met.no":
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("MarineSimulator/1.0") == true)
                return .ok(
                    """
                    {
                      "properties": {
                        "timeseries": [
                          {
                            "time": "2026-04-10T12:00:00Z",
                            "data": {
                              "instant": {
                                "details": {
                                  "wind_speed": 10.0,
                                  "wind_speed_of_gust": 14.0,
                                  "wind_from_direction": 225.0,
                                  "air_temperature": 19.5,
                                  "relative_humidity": 72.0,
                                  "air_pressure_at_sea_level": 1016.4
                                }
                              }
                            }
                          }
                        ]
                      }
                    }
                    """
                )
            case "marine-api.open-meteo.com":
                return .ok(
                    """
                    {
                      "current": {
                        "sea_surface_temperature": 15.8
                      }
                    }
                    """
                )
            default:
                throw StubTestError.missingURL
            }
        }
        let atmospheric = METNorwayWeatherService(session: sharedSession)
        let marine = OpenMeteoMarineTemperatureService(session: sharedSession)
        let service = GlobalFallbackWeatherService(atmospheric: atmospheric, marineTemperature: marine)

        let snapshot = try await service.fetchWeather(
            latitude: 43.19542,
            longitude: 27.89615,
            date: Date(timeIntervalSince1970: 1_775_822_400)
        )

        #expect(snapshot.sourceName == "MET Norway")
        #expect(snapshot.trueWindDirection == 225)
        #expect(abs((snapshot.trueWindSpeedKnots ?? 0) - 19.438444924406) < 0.001)
        #expect(abs((snapshot.windGustSpeedKnots ?? 0) - 27.2138228941684) < 0.001)
        #expect(snapshot.airTemperatureCelsius == 19.5)
        #expect(snapshot.relativeHumidityPercent == 72)
        #expect(snapshot.airPressureHectopascals == 1016.4)
        #expect(snapshot.seaSurfaceTemperatureCelsius == 15.8)
        #expect(snapshot.marineSourceName == "Open-Meteo Marine")
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> StubURLProtocol.Response
    ) -> URLSession {
        StubURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func snapshot() -> [URLRequest] {
        lock.lock()
        let snapshot = requests
        lock.unlock()
        return snapshot
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response {
        case ok(String)
        case failure(Error)
    }

    static var handler: (@Sendable (URLRequest) throws -> Response)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try handler(request)
            guard let url = request.url else {
                throw StubTestError.missingURL
            }

            switch response {
            case .ok(let body):
                let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum StubTestError: Error {
    case missingURL
}

private final class SequencedStubWeatherService: WeatherService, @unchecked Sendable {
    let responses: [Result<LiveWeatherSnapshot, Error>]
    private let state = SequencedStubWeatherServiceState()

    init(responses: [Result<LiveWeatherSnapshot, Error>]) {
        self.responses = responses
    }

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        let result = responses[await state.nextIndex(maximum: responses.count - 1)]
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}

private actor SequencedStubWeatherServiceState {
    private var index = 0

    func nextIndex(maximum: Int) -> Int {
        let current = index
        if index < maximum {
            index += 1
        }
        return current
    }
}
