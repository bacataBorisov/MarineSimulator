import Foundation
import Testing
@testable import MarineSimulator

struct NMEASimulatorEngineTests {
    @Test
    func checksumMatchesKnownSentence() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())

        let checksummed = simulator.addChecksum(to: "$IIMWV,90,R,10.0,N,A")

        #expect(checksummed == "$IIMWV,90,R,10.0,N,A*2B\r\n")
    }

    @Test
    func mwdUsesTrueAndMagneticWindDirectionsFromSnapshot() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 12.3,
            magneticVariation: 10
        )

        let sentences = simulator.buildNMEASentences(talkerID: "II", type: .mwd, snapshot: snapshot)

        #expect(sentences.count == 1)
        #expect(sentences[0] == "$IIMWD,90.0,T,80.0,M,12.3,N,6.3,M*70\r\n")
    }

    @Test
    func mwvReferenceModeRelativeProducesRelativeSentence() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.mwvReferenceMode = .relative

        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 0,
            gyroHeading: 0,
            boatSpeed: 0
        )

        let sentences = simulator.buildNMEASentences(talkerID: "II", type: .mwv, snapshot: snapshot)

        #expect(sentences.count == 1)
        #expect(sentences[0].contains(",R,"))
        #expect(sentences[0].hasPrefix("$IIMWV,90,R,10.0,N,A"))
    }

    @Test
    func mwvRelativeUsesResolvedTrueHeadingWhenOnlyMagneticHeadingAndVariationExist() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.mwvReferenceMode = .relative

        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 80,
            gyroHeading: nil,
            magneticVariation: 10,
            boatSpeed: 0
        )

        let sentences = simulator.buildNMEASentences(talkerID: "II", type: .mwv, snapshot: snapshot)

        #expect(sentences == ["$IIMWV,0,R,10.0,N,A*12\r\n"])
    }

    @Test
    func simulatorSettingsDecodeFallsBackForOlderPayloads() throws {
        let json = """
        {
          "ip": "127.0.0.1",
          "port": 4950,
          "talkerID": "II",
          "isTimerSelected": true,
          "interval": 1,
          "sentenceToggles": {
            "shouldSendMWV": true,
            "shouldSendMWD": true,
            "shouldSendVPW": true,
            "shouldSendHDG": true,
            "shouldSendHDT": true,
            "shouldSendROT": true,
            "shouldSendRMC": true,
            "shouldSendGGA": true,
            "shouldSendVTG": true,
            "shouldSendGLL": true,
            "shouldSendGSA": true,
            "shouldSendGSV": true,
            "shouldSendZDA": true,
            "shouldSendDBT": true,
            "shouldSendDPT": true,
            "shouldSendVHW": true,
            "shouldSendVLW": true,
            "shouldSendVBW": true,
            "shouldSendMTW": true
          },
          "sensorToggles": {
            "hasAnemometer": true,
            "hasCompass": true,
            "hasGyro": true,
            "hasGPS": true,
            "hasAIS": false,
            "hasEchoSounder": true,
            "hasSpeedLog": true,
            "hasWaterTempSensor": true,
            "hasAirTempSensor": false,
            "hasHumidtySensor": false,
            "hasBarometer": false,
            "shouldSendGNSS": false,
            "shouldSendDSC": false
          },
          "twd": {
            "value": 90,
            "range": [0, 359],
            "centerValue": 90,
            "offset": 0
          },
          "tws": {
            "value": 10,
            "range": [0, 50],
            "centerValue": 10,
            "offset": 0
          },
          "speed": {
            "value": 6,
            "range": [0, 50],
            "centerValue": 6,
            "offset": 0
          },
          "depth": {
            "value": 12,
            "range": [0, 1000],
            "centerValue": 12,
            "offset": 0
          },
          "depthOffsetMeters": 0,
          "seaTemp": {
            "value": 18,
            "range": [0, 40],
            "centerValue": 18,
            "offset": 0
          },
          "heading": {
            "value": 120,
            "range": [0, 359],
            "centerValue": 120,
            "offset": 0
          },
          "gyroHeading": {
            "value": 121,
            "range": [0, 359.9],
            "centerValue": 121,
            "offset": 0
          },
          "gpsData": {
            "latitude": 43.19542,
            "longitude": 27.89615,
            "speedOverGround": 6,
            "courseOverGround": 90
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SimulatorSettings.self, from: json)

        #expect(decoded.sentenceIntervals.isEmpty)
        #expect(decoded.outputEndpoints.count == 1)
        #expect(decoded.outputEndpoints[0].host == "127.0.0.1")
        #expect(decoded.outputEndpoints[0].port == 4950)
        #expect(decoded.faultInjection.isEnabled == false)
        #expect(decoded.mwvReferenceMode == .relative)
        #expect(decoded.selectedPreset == nil)
    }

    @Test
    func persistedSettingsRoundTripThroughUserDefaults() {
        let defaults = isolatedDefaults()
        let suiteName = defaultsSuiteName(for: defaults)
        let simulator = NMEASimulator(userDefaults: defaults)

        simulator.ip = "192.168.1.77"
        simulator.port = 10110
        simulator.talkerID = "GP"
        simulator.isTimerSelected = false
        simulator.interval = 2.5
        simulator.mwvReferenceMode = .trueReference
        simulator.setInterval(3, for: .gsv)
        simulator.addOutputEndpoint()
        simulator.outputEndpoints[1].host = "192.168.1.88"
        simulator.outputEndpoints[1].port = 4951
        simulator.outputEndpoints[1].transport = .tcp

        let restored = NMEASimulator(userDefaults: defaults)

        #expect(restored.ip == "192.168.1.77")
        #expect(restored.port == 10110)
        #expect(restored.talkerID == "GP")
        #expect(restored.isTimerSelected == false)
        #expect(restored.interval == 2.5)
        #expect(restored.mwvReferenceMode == .trueReference)
        #expect(restored.sentenceInterval(for: .gsv) == 3)
        #expect(restored.outputEndpoints.count == 2)
        #expect(restored.outputEndpoints[1].host == "192.168.1.88")
        #expect(restored.outputEndpoints[1].transport == .tcp)

        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test
    func explicitLivePersistenceCapturesNestedValueEdits() {
        let defaults = isolatedDefaults()
        let suiteName = defaultsSuiteName(for: defaults)
        let simulator = NMEASimulator(userDefaults: defaults)

        simulator.twd.centerValue = 44
        simulator.twd.offset = 2
        simulator.twd.value = 44
        simulator.gpsData.latitude = 42.123456
        simulator.gpsData.longitude = 25.654321
        simulator.gpsData.speedOverGround = 8.2
        simulator.gpsData.courseOverGround = 147
        simulator.persistLiveSettings()

        let restored = NMEASimulator(userDefaults: defaults)

        #expect(restored.twd.centerValue == 44)
        #expect(restored.twd.offset == 2)
        #expect(restored.twd.value == 44)
        #expect(restored.gpsData.latitude == 42.123456)
        #expect(restored.gpsData.longitude == 25.654321)
        #expect(restored.gpsData.speedOverGround == 8.2)
        #expect(restored.gpsData.courseOverGround == 147)

        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test
    func applyingPresetUpdatesAndPersistsScenarioValues() {
        let defaults = isolatedDefaults()
        let suiteName = defaultsSuiteName(for: defaults)
        let simulator = NMEASimulator(userDefaults: defaults)

        simulator.applyPreset(.stormyWeather)

        #expect(simulator.selectedPreset == .stormyWeather)
        #expect(simulator.tws.centerValue == 32)
        #expect(simulator.speed.centerValue == 10.5)
        #expect(simulator.heading.centerValue == 200)
        #expect(simulator.gpsData.speedOverGround == 12)
        #expect(simulator.gpsData.courseOverGround == 202)

        let restored = NMEASimulator(userDefaults: defaults)

        #expect(restored.selectedPreset == .stormyWeather)
        #expect(restored.tws.centerValue == 32)
        #expect(restored.speed.centerValue == 10.5)
        #expect(restored.heading.centerValue == 200)
        #expect(restored.gpsData.speedOverGround == 12)
        #expect(restored.gpsData.courseOverGround == 202)

        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test
    func simulatorSettingsDecodeFallsBackForMissingLiveWeatherFields() throws {
        let json = """
        {
          "ip": "127.0.0.1",
          "port": 4950,
          "talkerID": "II",
          "outputEndpoints": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Primary Output",
              "host": "127.0.0.1",
              "port": 4950,
              "transport": "udp",
              "isEnabled": true
            }
          ],
          "sentenceIntervals": {},
          "isTimerSelected": true,
          "interval": 1,
          "sentenceToggles": {
            "shouldSendMWV": true,
            "shouldSendMWD": true,
            "shouldSendVPW": true,
            "shouldSendHDG": true,
            "shouldSendHDT": true,
            "shouldSendROT": true,
            "shouldSendRMC": true,
            "shouldSendGGA": true,
            "shouldSendVTG": true,
            "shouldSendGLL": true,
            "shouldSendGSA": true,
            "shouldSendGSV": true,
            "shouldSendZDA": true,
            "shouldSendDBT": true,
            "shouldSendDPT": true,
            "shouldSendVHW": true,
            "shouldSendVLW": true,
            "shouldSendVBW": true,
            "shouldSendMTW": true
          },
          "sensorToggles": {
            "hasAnemometer": true,
            "hasCompass": true,
            "hasGyro": true,
            "hasGPS": true,
            "hasAIS": false,
            "hasEchoSounder": true,
            "hasSpeedLog": true,
            "hasWaterTempSensor": true,
            "hasAirTempSensor": false,
            "hasHumidtySensor": false,
            "hasBarometer": false,
            "shouldSendGNSS": false,
            "shouldSendDSC": false
          },
          "twd": {
            "value": 90,
            "range": [0, 359],
            "centerValue": 90,
            "offset": 0
          },
          "tws": {
            "value": 10,
            "range": [0, 50],
            "centerValue": 10,
            "offset": 0
          },
          "speed": {
            "value": 6,
            "range": [0, 50],
            "centerValue": 6,
            "offset": 0
          },
          "depth": {
            "value": 12,
            "range": [0, 1000],
            "centerValue": 12,
            "offset": 0
          },
          "depthOffsetMeters": 0,
          "seaTemp": {
            "value": 18,
            "range": [0, 40],
            "centerValue": 18,
            "offset": 0
          },
          "heading": {
            "value": 120,
            "range": [0, 359],
            "centerValue": 120,
            "offset": 0
          },
          "gyroHeading": {
            "value": 121,
            "range": [0, 359.9],
            "centerValue": 121,
            "offset": 0
          },
          "gpsData": {
            "latitude": 43.19542,
            "longitude": 27.89615,
            "speedOverGround": 6,
            "courseOverGround": 90
          },
          "faultInjection": {
            "isEnabled": false,
            "dropRate": 0,
            "delayRate": 0,
            "checksumCorruptionRate": 0,
            "invalidDataRate": 0,
            "maximumDelayCycles": 2
          },
          "mwvReferenceMode": "relative",
          "selectedPreset": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SimulatorSettings.self, from: json)

        #expect(decoded.weatherSourceMode == .manual)
        #expect(decoded.liveWeatherSettings == LiveWeatherSettings())
        #expect(decoded.latestLiveWeather == nil)
    }

    @Test
    func liveWeatherSettingsPersistAcrossRestore() async {
        let defaults = isolatedDefaults()
        let suiteName = defaultsSuiteName(for: defaults)
        let simulator = NMEASimulator(
            userDefaults: defaults,
            weatherService: StubWeatherService(snapshot: makeLiveWeatherSnapshot())
        )

        simulator.weatherSourceMode = .liveWeather
        simulator.liveWeatherSettings.refreshIntervalMinutes = 20
        simulator.liveWeatherSettings.minimumRefreshDistanceNM = 7
        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        let restored = NMEASimulator(
            userDefaults: defaults,
            weatherService: StubWeatherService(snapshot: makeLiveWeatherSnapshot())
        )

        #expect(restored.weatherSourceMode == .liveWeather)
        #expect(restored.liveWeatherSettings.refreshIntervalMinutes == 20)
        #expect(restored.liveWeatherSettings.minimumRefreshDistanceNM == 7)
        #expect(restored.latestLiveWeather?.trueWindDirection == 145)
        #expect(restored.latestLiveWeather?.trueWindSpeedKnots == 18)

        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test
    func liveWeatherOverridesWindAndSeaTemperatureDuringSimulationCycle() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: StubWeatherService(snapshot: makeLiveWeatherSnapshot())
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather

        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))
        simulator.sendAllSelectedNMEA()

        #expect(abs((simulator.latestSnapshot?.windDirectionTrue ?? 0) - 145) <= 6.1)
        #expect(abs((simulator.latestSnapshot?.windSpeedTrue ?? 0) - 18) <= 0.91)
        #expect(abs((simulator.latestSnapshot?.seaTemperature ?? 0) - 16.4) <= 0.31)
    }

    @Test
    func liveWeatherAddsSmallVariationBetweenFetches() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: StubWeatherService(snapshot: makeLiveWeatherSnapshot())
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather

        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        simulator.sendAllSelectedNMEA()
        let firstSnapshot = simulator.latestSnapshot

        simulator.sendAllSelectedNMEA()
        let secondSnapshot = simulator.latestSnapshot

        #expect(firstSnapshot?.windDirectionTrue != nil)
        #expect(firstSnapshot?.windSpeedTrue != nil)
        #expect(firstSnapshot?.seaTemperature != nil)

        #expect(abs((firstSnapshot?.windDirectionTrue ?? 0) - 145) <= 6.1)
        #expect(abs((firstSnapshot?.windSpeedTrue ?? 0) - 18) <= 0.91)
        #expect(abs((firstSnapshot?.seaTemperature ?? 0) - 16.4) <= 0.31)

        #expect(abs((secondSnapshot?.windDirectionTrue ?? 0) - 145) <= 6.1)
        #expect(abs((secondSnapshot?.windSpeedTrue ?? 0) - 18) <= 0.91)
        #expect(abs((secondSnapshot?.seaTemperature ?? 0) - 16.4) <= 0.31)
    }

    @Test
    func switchingToLiveWeatherClearsPresetAndFetchesFreshWeather() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: DelayedStubWeatherService(
                snapshot: makeLiveWeatherSnapshot(),
                delayNanoseconds: 50_000_000
            )
        )

        simulator.applyPreset(.stormyWeather)
        #expect(simulator.selectedPreset == .stormyWeather)

        simulator.weatherSourceMode = .liveWeather

        #expect(simulator.selectedPreset == nil)
        #expect(simulator.latestLiveWeather == nil)
        #expect(simulator.twd.value == nil)
        #expect(simulator.tws.value == nil)
        #expect(simulator.seaTemp.value == nil)

        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(simulator.latestLiveWeather?.trueWindDirection == 145)
        #expect(simulator.latestLiveWeather?.trueWindSpeedKnots == 18)
        #expect(simulator.latestLiveWeather?.seaSurfaceTemperatureCelsius == 16.4)
    }

    @Test
    func liveWeatherStartWaitsForFreshFetchBeforeTransmitting() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: DelayedStubWeatherService(
                snapshot: makeLiveWeatherSnapshot(),
                delayNanoseconds: 50_000_000
            )
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather
        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        simulator.startSimulation()

        #expect(simulator.latestLiveWeather?.trueWindDirection == 145)
        #expect(simulator.isTransmitting == true)

        simulator.stopSimulation()
    }

    @Test
    func liveWeatherStartUsesCachedWeatherImmediately() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: StubWeatherService(snapshot: makeLiveWeatherSnapshot())
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather
        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        simulator.startSimulation()

        #expect(simulator.isTransmitting == true)
        #expect(simulator.latestLiveWeather?.trueWindDirection == 145)

        simulator.stopSimulation()
    }

    @Test
    func liveWeatherRemainsVisibleAfterStoppingSimulation() async {
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: StubWeatherService(snapshot: makeLiveWeatherSnapshot())
        )
        simulator.outputEndpoints[0].isEnabled = false
        simulator.weatherSourceMode = .liveWeather
        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))

        simulator.startSimulation()
        simulator.stopSimulation()

        #expect(simulator.isTransmitting == false)
        #expect(simulator.twd.value == 145)
        #expect(simulator.tws.value == 18)
        #expect(simulator.seaTemp.value == 16.4)
        #expect(simulator.calculatedTWD == 145)
    }

    @Test
    func failedLiveWeatherRefreshKeepsLastGoodSnapshotVisible() async {
        let service = SequencedWeatherService(responses: [
            .success(makeLiveWeatherSnapshot()),
            .failure(WeatherServiceError.requestTimedOut)
        ])
        let simulator = NMEASimulator(
            userDefaults: isolatedDefaults(),
            weatherService: service
        )
        simulator.weatherSourceMode = .liveWeather

        _ = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_000))
        let refreshSucceeded = await simulator.refreshLiveWeatherNow(force: true, at: Date(timeIntervalSince1970: 1_700_000_100))

        #expect(refreshSucceeded == false)
        #expect(simulator.latestLiveWeather?.trueWindDirection == 145)
        #expect(simulator.liveWeatherStatus.state == .failed)
        #expect(simulator.liveWeatherStatus.lastUpdated == simulator.latestLiveWeather?.fetchedAt)
        #expect(simulator.liveWeatherStatus.message.contains("Using last good weather"))
    }

    @Test
    func startSimulationWithoutTimerSendsOneBurstAndStops() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false

        simulator.startSimulation()

        #expect(simulator.isTransmitting == false)
        #expect(simulator.outputMessages.isEmpty == false)
        #expect(simulator.transportHistory.contains { $0.category == .lifecycle && $0.message == "Single transmission sent" })
    }

    @Test
    func faultInjectionCanDropAllSentences() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 1
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 0

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.isEmpty)
        #expect(simulator.transportHistory.contains { $0.category == .fault })
    }

    @Test
    func headingSentenceFamilyBuildsExpectedPayloads() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 123.4,
            gyroHeading: 126.4,
            magneticVariation: 4.5
        )

        let hdg = simulator.buildNMEASentences(talkerID: "II", type: .hdg, snapshot: snapshot)
        let hdt = simulator.buildNMEASentences(talkerID: "II", type: .hdt, snapshot: snapshot)
        let rot = simulator.buildNMEASentences(talkerID: "II", type: .rot, snapshot: snapshot)

        #expect(hdg == ["$IIHDG,123.4,0.0,E,4.5,E*4C\r\n"])
        #expect(hdt == ["$IIHDT,126.4,T*23\r\n"])
        #expect(rot == ["$IIROT,0.0,V*31\r\n"])
    }

    @Test
    func hydroSentenceFamilyBuildsExpectedPayloads() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.depthOffsetMeters = 0.3
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 100,
            gyroHeading: 105,
            magneticVariation: 5,
            boatSpeed: 6
        )

        let dbt = simulator.buildNMEASentences(talkerID: "II", type: .dbt, snapshot: snapshot)
        let dpt = simulator.buildNMEASentences(talkerID: "II", type: .dpt, snapshot: snapshot)
        let mtw = simulator.buildNMEASentences(talkerID: "II", type: .mtw, snapshot: snapshot)
        let vhw = simulator.buildNMEASentences(talkerID: "II", type: .vhw, snapshot: snapshot)
        let vbw = simulator.buildNMEASentences(talkerID: "II", type: .vbw, snapshot: snapshot)
        let vlw = simulator.buildNMEASentences(talkerID: "II", type: .vlw, snapshot: snapshot)

        #expect(dbt == ["$IIDBT,39.4,f,12.0,M,6.6,F*1C\r\n"])
        #expect(dpt == ["$IIDPT,12.0,0.3*70\r\n"])
        #expect(mtw == ["$IIMTW,18.0,C*1A\r\n"])
        #expect(vhw == ["$IIVHW,105.0,T,100.0,M,6.0,N,11.1,K*67\r\n"])
        #expect(vbw == ["$IIVBW,6.0,0.0,A,5.8,-1.6,A*62\r\n"])
        #expect(vlw == ["$IIVLW,1.20,N,0.40,N*4A\r\n"])
    }

    @Test
    func gpsSentenceFamilyBuildsExpectedPayloads() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = makeSnapshot(
            timestamp: timestamp,
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 120,
            gyroHeading: 124,
            magneticVariation: 4.5,
            boatSpeed: 6
        )

        #expect(simulator.buildNMEASentences(talkerID: "II", type: .rmc, snapshot: snapshot) == ["$IIRMC,221320.00,A,4311.7252,N,02753.7690,E,6.0,90.0,141123,4.5,E,A*16\r\n"])
        #expect(simulator.buildNMEASentences(talkerID: "II", type: .gga, snapshot: snapshot) == ["$IIGGA,221320.00,4311.7252,N,02753.7690,E,1,08,0.9,14.2,M,36.1,M,,*47\r\n"])
        #expect(simulator.buildNMEASentences(talkerID: "II", type: .vtg, snapshot: snapshot) == ["$IIVTG,90.0,T,85.5,M,6.0,N,11.1,K,A*02\r\n"])
        #expect(simulator.buildNMEASentences(talkerID: "II", type: .gll, snapshot: snapshot) == ["$IIGLL,4311.7252,N,02753.7690,E,221320.00,A,A*70\r\n"])
        #expect(simulator.buildNMEASentences(talkerID: "II", type: .gsa, snapshot: snapshot) == ["$IIGSA,A,3,01,02,03,04,,,,,,,,,1.4,0.9,1.1*2D\r\n"])
        #expect(simulator.buildNMEASentences(talkerID: "II", type: .zda, snapshot: snapshot) == ["$IIZDA,221320.00,14,11,2023,00,00*77\r\n"])

        let gsv = simulator.buildNMEASentences(talkerID: "II", type: .gsv, snapshot: snapshot)
        #expect(gsv == ["$IIGSV,1,1,4,01,45,120,35,02,50,180,38,03,30,240,28,04,20,300,22*53\r\n"])
    }

    @Test
    func windMathRemainsConsistentForMovingBoat() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 0,
            gyroHeading: 0,
            magneticVariation: 0,
            boatSpeed: 6
        )

        let twa = simulator.computeTWA(from: snapshot)
        let awa = simulator.computeAWA(from: snapshot)
        let aws = simulator.computeAWS(from: snapshot)
        let awd = simulator.computeAWD(from: snapshot)
        let vpwKnots = simulator.computeVPWKnots(from: snapshot)

        #expect(twa == 90)
        #expect(awa == 59.03624346792648)
        #expect(aws == 11.661903789690601)
        #expect(awd == 59.03624346792648)
        #expect(vpwKnots == 6.123233995736766e-16)
    }

    @Test
    func windMathUsesTrueHeadingForMagneticOnlySnapshots() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 80,
            gyroHeading: nil,
            magneticVariation: 10,
            boatSpeed: 0
        )

        #expect(simulator.computeTWA(from: snapshot) == 0)
        #expect(simulator.computeAWA(from: snapshot) == 0)
        #expect(simulator.computeAWD(from: snapshot) == 90)
    }

    @Test
    func windMathPrefersGyroHeadingOverMagneticHeadingWhenBothExist() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 150,
            windSpeedTrue: 10,
            magneticHeading: 70,
            gyroHeading: 120,
            magneticVariation: 25,
            boatSpeed: 0
        )

        #expect(simulator.computeTWA(from: snapshot) == 30)
        #expect(simulator.computeAWA(from: snapshot) == 30)
        #expect(simulator.computeAWD(from: snapshot) == 150)
    }

    @Test
    func idleWindDisplayRespondsImmediatelyToHeadingChanges() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sensorToggles.hasGyro = false
        simulator.twd.value = 90
        simulator.heading.value = 90
        simulator.sendAllSelectedNMEA()

        let initialTWA = simulator.calculatedTWA
        #expect(initialTWA != nil)

        simulator.heading.value = 120

        #expect(simulator.calculatedTWA == normalizeAngle((initialTWA ?? 0) - 30))
    }

    @Test
    func windSentenceEdgeCasesRemainValidAtCardinalAndWraparoundAngles() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.mwvReferenceMode = .relative
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            makeSnapshot(timestamp: timestamp, windDirectionTrue: 0, windSpeedTrue: 12, magneticHeading: 0, gyroHeading: nil, magneticVariation: 0, boatSpeed: 0),
            makeSnapshot(timestamp: timestamp, windDirectionTrue: 90, windSpeedTrue: 12, magneticHeading: 0, gyroHeading: nil, magneticVariation: 0, boatSpeed: 0),
            makeSnapshot(timestamp: timestamp, windDirectionTrue: 180, windSpeedTrue: 12, magneticHeading: 0, gyroHeading: nil, magneticVariation: 0, boatSpeed: 0),
            makeSnapshot(timestamp: timestamp, windDirectionTrue: 350, windSpeedTrue: 12, magneticHeading: 10, gyroHeading: nil, magneticVariation: 0, boatSpeed: 0)
        ]

        let sentences = snapshots.flatMap { snapshot in
            simulator.buildNMEASentences(talkerID: "II", type: .mwv, snapshot: snapshot) +
            simulator.buildNMEASentences(talkerID: "II", type: .mwd, snapshot: snapshot)
        }

        #expect(sentences.isEmpty == false)
        #expect(sentences.allSatisfy(isValidNMEASentence))
        #expect(sentences.contains("$IIMWV,340,R,12.0,N,A*17\r\n"))
        #expect(sentences.contains("$IIMWD,350.0,T,350.0,M,12.0,N,6.2,M*73\r\n"))
    }

    @Test
    func sentenceIntervalsSuppressImmediateRepeatBursts() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.setInterval(60, for: .rmc)

        simulator.sendAllSelectedNMEA()
        let firstBurstCount = simulator.outputMessages.filter { $0.hasPrefix("$IIRMC") }.count

        simulator.sendAllSelectedNMEA()
        let secondBurstCount = simulator.outputMessages.filter { $0.hasPrefix("$IIRMC") }.count

        #expect(firstBurstCount == 1)
        #expect(secondBurstCount == 1)
    }

    @Test
    func disabledSensorsSuppressDependentSentences() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sensorToggles.hasAnemometer = false
        simulator.sensorToggles.hasGPS = false

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.contains(where: { $0.contains("MWV") }) == false)
        #expect(simulator.outputMessages.contains(where: { $0.contains("MWD") }) == false)
        #expect(simulator.outputMessages.contains(where: { $0.contains("RMC") }) == false)
        #expect(simulator.outputMessages.contains(where: { $0.contains("GGA") }) == false)
    }

    @Test
    func invalidDepthOffsetSuppressesDpt() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.depthOffsetMeters = 120

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.contains(where: { $0.contains("DPT") }) == false)
        #expect(simulator.outputMessages.contains(where: { $0.contains("DBT") }))
    }

    @Test
    func hdtFallsBackToMagneticHeadingPlusVariationWhenGyroMissing() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 350,
            gyroHeading: nil,
            magneticVariation: 15
        )

        let hdt = simulator.buildNMEASentences(talkerID: "II", type: .hdt, snapshot: snapshot)

        #expect(hdt == ["$IIHDT,5.0,T*27\r\n"])
    }

    @Test
    func windAnglesNormalizeAcrossNorthWraparound() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 10,
            windSpeedTrue: 12,
            magneticHeading: 350,
            gyroHeading: nil,
            magneticVariation: 0,
            boatSpeed: 0
        )

        #expect(simulator.computeTWA(from: snapshot) == 20)
        #expect(simulator.computeAWA(from: snapshot) == 20)
        #expect(simulator.computeAWD(from: snapshot) == 10)
    }

    @Test
    func mwvAutoModeAlternatesBetweenRelativeAndTrueWhenBothExist() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.mwvReferenceMode = .auto
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 0,
            gyroHeading: 0,
            magneticVariation: 0,
            boatSpeed: 6
        )

        let first = simulator.buildNMEASentences(talkerID: "II", type: .mwv, snapshot: snapshot)
        let second = simulator.buildNMEASentences(talkerID: "II", type: .mwv, snapshot: snapshot)

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first[0].contains(",R,"))
        #expect(second[0].contains(",T,"))
    }

    @Test
    func checksumCorruptionRewritesChecksumToZeroes() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.invalidDataRate = 0
        simulator.faultInjection.checksumCorruptionRate = 1

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.isEmpty == false)
        #expect(simulator.outputMessages.allSatisfy { $0.hasSuffix("*00\r\n") })
        #expect(simulator.transportHistory.contains { $0.category == .fault && $0.message.contains("Corrupted checksum") })
    }

    @Test
    func invalidDataFaultMarksRmcAsVoid() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendRMC)
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 1

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.count == 1)
        #expect(simulator.outputMessages[0].contains(",V,"))
        #expect(simulator.transportHistory.contains { $0.category == .fault && $0.message.contains("Injected invalid data") })
    }

    @Test
    func invalidDataFaultMarksGgaWithoutFix() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendGGA)
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 1

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.count == 1)
        #expect(simulator.outputMessages[0].contains(",0,00,"))
    }

    @Test
    func invalidDataFaultMarksGllAsVoid() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendGLL)
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 1

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.count == 1)
        #expect(simulator.outputMessages[0].contains(",V,"))
    }

    @Test
    func invalidDataFaultMarksVtgNavigationModeInvalid() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendVTG)
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 1

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.count == 1)
        #expect(simulator.outputMessages[0].contains(",N*"))
    }

    @Test
    func invalidDataFaultMarksRotStatusVoid() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles = onlyEnabledSentence(\.shouldSendROT)
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 0
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 1

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.count == 1)
        #expect(simulator.outputMessages[0].contains(",V*"))
    }

    @Test
    func delayedFaultQueuesSentenceUntilLaterCycle() throws {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.interval = 0.1
        simulator.sentenceToggles.shouldSendMWV = false
        simulator.sentenceToggles.shouldSendMWD = false
        simulator.sentenceToggles.shouldSendVPW = false
        simulator.sentenceToggles.shouldSendHDG = false
        simulator.sentenceToggles.shouldSendHDT = false
        simulator.sentenceToggles.shouldSendROT = false
        simulator.sentenceToggles.shouldSendGGA = false
        simulator.sentenceToggles.shouldSendVTG = false
        simulator.sentenceToggles.shouldSendGLL = false
        simulator.sentenceToggles.shouldSendGSA = false
        simulator.sentenceToggles.shouldSendGSV = false
        simulator.sentenceToggles.shouldSendZDA = false
        simulator.sentenceToggles.shouldSendDBT = false
        simulator.sentenceToggles.shouldSendDPT = false
        simulator.sentenceToggles.shouldSendVHW = false
        simulator.sentenceToggles.shouldSendVBW = false
        simulator.sentenceToggles.shouldSendVLW = false
        simulator.sentenceToggles.shouldSendMTW = false
        simulator.faultInjection.isEnabled = true
        simulator.faultInjection.dropRate = 0
        simulator.faultInjection.delayRate = 1
        simulator.faultInjection.checksumCorruptionRate = 0
        simulator.faultInjection.invalidDataRate = 0
        simulator.faultInjection.maximumDelayCycles = 1

        simulator.sendAllSelectedNMEA()
        #expect(simulator.outputMessages.isEmpty)

        simulator.faultInjection.delayRate = 0
        Thread.sleep(forTimeInterval: 0.12)
        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.contains(where: { $0.hasPrefix("$IIRMC") }))
        #expect(simulator.transportHistory.contains { $0.category == .fault && $0.message.contains("Delayed RMC") })
    }

    @Test
    func gsvSplitsIntoMultipleSentencesWhenMoreThanFourSatellitesExist() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 120,
            gyroHeading: 124,
            magneticVariation: 4.5,
            boatSpeed: 6,
            gpsSignal: GPSSignalSnapshot(
                fixQuality: 1,
                fixMode: 3,
                selectionMode: "A",
                satellitesUsed: 6,
                hdop: 0.9,
                vdop: 1.1,
                pdop: 1.4,
                altitudeMeters: 14.2,
                geoidalSeparationMeters: 36.1,
                satellites: [
                    GPSSatelliteSnapshot(prn: 1, elevation: 45, azimuth: 120, snr: 35, isUsedInFix: true),
                    GPSSatelliteSnapshot(prn: 2, elevation: 50, azimuth: 180, snr: 38, isUsedInFix: true),
                    GPSSatelliteSnapshot(prn: 3, elevation: 30, azimuth: 240, snr: 28, isUsedInFix: true),
                    GPSSatelliteSnapshot(prn: 4, elevation: 20, azimuth: 300, snr: 22, isUsedInFix: true),
                    GPSSatelliteSnapshot(prn: 5, elevation: 15, azimuth: 20, snr: 25, isUsedInFix: false)
                ]
            )
        )

        let gsv = simulator.buildNMEASentences(talkerID: "II", type: .gsv, snapshot: snapshot)

        #expect(gsv.count == 2)
        #expect(gsv[0].hasPrefix("$IIGSV,2,1,5,"))
        #expect(gsv[1].hasPrefix("$IIGSV,2,2,5,"))
    }

    @Test
    func primaryEndpointTransportSurvivesIpAndPortChanges() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())

        simulator.outputEndpoints[0].transport = .tcp
        simulator.ip = "10.0.0.25"
        simulator.port = 2000

        #expect(simulator.outputEndpoints[0].transport == .tcp)
        #expect(simulator.outputEndpoints[0].host == "10.0.0.25")
        #expect(simulator.outputEndpoints[0].port == 2000)
    }

    @Test
    func vhwRequiresSpeedLogAndHeadingSource() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles.shouldSendMWV = false
        simulator.sentenceToggles.shouldSendMWD = false
        simulator.sentenceToggles.shouldSendVPW = false
        simulator.sentenceToggles.shouldSendHDG = false
        simulator.sentenceToggles.shouldSendHDT = false
        simulator.sentenceToggles.shouldSendROT = false
        simulator.sentenceToggles.shouldSendRMC = false
        simulator.sentenceToggles.shouldSendGGA = false
        simulator.sentenceToggles.shouldSendVTG = false
        simulator.sentenceToggles.shouldSendGLL = false
        simulator.sentenceToggles.shouldSendGSA = false
        simulator.sentenceToggles.shouldSendGSV = false
        simulator.sentenceToggles.shouldSendZDA = false
        simulator.sentenceToggles.shouldSendDBT = false
        simulator.sentenceToggles.shouldSendDPT = false
        simulator.sentenceToggles.shouldSendVBW = false
        simulator.sentenceToggles.shouldSendVLW = false
        simulator.sentenceToggles.shouldSendMTW = false

        simulator.sensorToggles.hasCompass = false
        simulator.sensorToggles.hasGyro = false
        simulator.sendAllSelectedNMEA()
        #expect(simulator.outputMessages.contains(where: { $0.contains("VHW") }) == false)

        simulator.outputMessages.removeAll()
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasSpeedLog = false
        simulator.sendAllSelectedNMEA()
        #expect(simulator.outputMessages.contains(where: { $0.contains("VHW") }) == false)
    }

    @Test
    func vtgUsesMagneticVariationForMagneticCourseField() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            windDirectionTrue: 90,
            windSpeedTrue: 10,
            magneticHeading: 120,
            gyroHeading: 124,
            magneticVariation: 7.5,
            boatSpeed: 6
        )

        let vtg = simulator.buildNMEASentences(talkerID: "II", type: .vtg, snapshot: snapshot)

        #expect(vtg == ["$IIVTG,90.0,T,82.5,M,6.0,N,11.1,K,A*05\r\n"])
    }

    @Test
    func vbwBlanksGroundTrackFieldsWhenGpsIsUnavailable() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sentenceToggles.shouldSendMWV = false
        simulator.sentenceToggles.shouldSendMWD = false
        simulator.sentenceToggles.shouldSendVPW = false
        simulator.sentenceToggles.shouldSendHDG = false
        simulator.sentenceToggles.shouldSendHDT = false
        simulator.sentenceToggles.shouldSendROT = false
        simulator.sentenceToggles.shouldSendRMC = false
        simulator.sentenceToggles.shouldSendGGA = false
        simulator.sentenceToggles.shouldSendVTG = false
        simulator.sentenceToggles.shouldSendGLL = false
        simulator.sentenceToggles.shouldSendGSA = false
        simulator.sentenceToggles.shouldSendGSV = false
        simulator.sentenceToggles.shouldSendZDA = false
        simulator.sentenceToggles.shouldSendDBT = false
        simulator.sentenceToggles.shouldSendDPT = false
        simulator.sentenceToggles.shouldSendVHW = false
        simulator.sentenceToggles.shouldSendVLW = false
        simulator.sentenceToggles.shouldSendMTW = false
        simulator.sensorToggles.hasGPS = false

        simulator.sendAllSelectedNMEA()

        #expect(simulator.outputMessages.count == 1)
        #expect(simulator.outputMessages[0] == "$IIVBW,6.0,0.0,A,,,V*52\r\n")
    }

    @Test
    func firstSimulationBurstDoesNotAdvanceGpsPositionArtificially() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.interval = 5
        let originalLatitude = simulator.gpsData.latitude
        let originalLongitude = simulator.gpsData.longitude

        simulator.startSimulation()

        #expect(simulator.gpsData.latitude == originalLatitude)
        #expect(simulator.gpsData.longitude == originalLongitude)
    }

    @Test
    func disablingTimerWhileRunningStopsContinuousTransmission() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = true

        simulator.startSimulation()
        #expect(simulator.isTransmitting == true)

        simulator.isTimerSelected = false

        #expect(simulator.isTransmitting == false)
        #expect(simulator.transportHistory.contains { $0.category == .lifecycle && $0.message == "Timer disabled; continuous transmission stopped" })
    }

    @Test
    func outputMessagesAreTrimmedToMostRecentHundredLines() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false

        for _ in 0..<30 {
            simulator.startSimulation()
        }

        #expect(simulator.outputMessages.count == 100)
    }

    @Test
    func transportHistoryIsTrimmedToMostRecentTwoHundredEvents() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false

        for _ in 0..<250 {
            simulator.startSimulation()
        }

        #expect(simulator.transportHistory.count == 200)
    }

    @Test
    func removingPrimaryOutputEndpointIsIgnored() {
        let simulator = configuredSimulatorForDeterministicOutput()
        let primaryID = simulator.outputEndpoints[0].id

        simulator.removeOutputEndpoint(id: primaryID)

        #expect(simulator.outputEndpoints.count == 1)
        #expect(simulator.outputEndpoints[0].id == primaryID)
    }

    @Test
    func removingSecondaryEndpointClearsStoredTransportStatus() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.addOutputEndpoint()
        let secondaryID = simulator.outputEndpoints[1].id

        simulator.stopSimulation()
        #expect(simulator.transportStatus(for: secondaryID)?.level == .idle)

        simulator.removeOutputEndpoint(id: secondaryID)

        #expect(simulator.outputEndpoints.count == 1)
        #expect(simulator.transportStatus(for: secondaryID) == nil)
    }

    @Test
    func changingSecondaryEndpointWhileRunningDoesNotAffectPrimaryDestination() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.addOutputEndpoint()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.outputEndpoints[1].host = "192.168.10.50"
        simulator.outputEndpoints[1].port = 6000
        simulator.isTimerSelected = true

        simulator.startSimulation()
        simulator.outputEndpoints[1].host = "192.168.10.99"
        simulator.outputEndpoints[1].port = 7000

        #expect(simulator.ip == "127.0.0.1")
        #expect(simulator.port == 4950)
        #expect(simulator.outputEndpoints[0].host == "127.0.0.1")
        #expect(simulator.outputEndpoints[0].port == 4950)
        #expect(simulator.outputEndpoints[1].host == "192.168.10.99")
        #expect(simulator.outputEndpoints[1].port == 7000)
    }

    @Test
    func disablingSecondaryEndpointWhileRunningKeepsSimulationAlive() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.addOutputEndpoint()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.outputEndpoints[1].isEnabled = true
        simulator.isTimerSelected = true

        simulator.startSimulation()
        simulator.outputEndpoints[1].isEnabled = false

        #expect(simulator.isTransmitting == true)
        #expect(simulator.outputEndpoints[1].isEnabled == false)
        #expect(simulator.outputEndpoints[0].isEnabled == true)
    }

    @Test
    func changingSecondaryEndpointTransportWhileRunningPreservesSelection() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.addOutputEndpoint()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.outputEndpoints[1].transport = .udp
        simulator.isTimerSelected = true

        simulator.startSimulation()
        simulator.outputEndpoints[1].transport = .tcp

        #expect(simulator.isTransmitting == true)
        #expect(simulator.outputEndpoints[1].transport == .tcp)
        #expect(simulator.outputEndpoints[0].transport == .udp)
    }

    @Test
    func removingSecondaryEndpointWhileRunningKeepsSimulationAlive() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.addOutputEndpoint()
        let secondaryID = simulator.outputEndpoints[1].id
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = true

        simulator.startSimulation()
        simulator.removeOutputEndpoint(id: secondaryID)

        #expect(simulator.isTransmitting == true)
        #expect(simulator.outputEndpoints.count == 1)
        #expect(simulator.transportStatus(for: secondaryID) == nil)
    }

    @Test
    func restartingAfterSecondaryEndpointEditsKeepsLatestStatusConsistent() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.addOutputEndpoint()
        simulator.outputEndpoints[1].host = "192.168.4.20"
        simulator.outputEndpoints[1].port = 10110
        simulator.outputEndpoints[1].transport = .tcp
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = true

        simulator.startSimulation()
        simulator.outputEndpoints[1].isEnabled = false
        simulator.stopSimulation()

        #expect(simulator.latestTransportStatus?.level == .idle)

        simulator.outputEndpoints[1].isEnabled = true
        simulator.startSimulation()

        #expect(simulator.isTransmitting == true)
        #expect(simulator.outputEndpoints[1].transport == .tcp)
        #expect(simulator.latestTransportStatus != nil)
    }

    @Test
    func sentenceIntervalClampsNegativeValuesToZero() {
        let simulator = configuredSimulatorForDeterministicOutput()

        simulator.setInterval(-5, for: .rmc)

        #expect(simulator.sentenceInterval(for: .rmc) == 0)
    }

    @Test
    func globalTimerIntervalClampsToPositiveMinimum() {
        let simulator = configuredSimulatorForDeterministicOutput()

        simulator.interval = -2

        #expect(simulator.interval == 0.1)
    }

    @Test
    func restartingSimulationResetsTripDistanceAndEmissionSchedule() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.interval = 1
        simulator.isTimerSelected = false
        simulator.setInterval(60, for: .rmc)

        simulator.startSimulation()
        let firstBurstMessages = simulator.outputMessages

        simulator.startSimulation()
        let secondBurstMessages = simulator.outputMessages.suffix(firstBurstMessages.count)

        #expect(firstBurstMessages.contains(where: { $0.hasPrefix("$IIRMC") }))
        #expect(secondBurstMessages.contains(where: { $0.hasPrefix("$IIRMC") }))
        #expect(secondBurstMessages.contains(where: { $0.hasPrefix("$IIVLW,") && $0.contains(",0.00,N") }))
    }

    @Test
    func changingPrimaryEndpointTransportWhileIdlePreservesNewTransport() {
        let simulator = configuredSimulatorForDeterministicOutput()

        simulator.outputEndpoints[0].transport = .tcp
        simulator.outputEndpoints[0].host = "192.168.0.50"
        simulator.outputEndpoints[0].port = 10110

        #expect(simulator.ip == "192.168.0.50")
        #expect(simulator.port == 10110)
        #expect(simulator.outputEndpoints[0].transport == .tcp)
    }

    @Test
    func primaryEndpointIsReenabledWhenSimulationStarts() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.isTimerSelected = false
        simulator.outputEndpoints[0].isEnabled = false

        simulator.startSimulation()

        #expect(simulator.outputEndpoints[0].isEnabled == true)
    }

    @Test
    func stopSimulationMarksEndpointsIdle() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].transport = .tcp
        simulator.outputEndpoints[0].isEnabled = false
        simulator.startSimulation()

        simulator.stopSimulation()

        let status = simulator.transportStatus(for: simulator.outputEndpoints[0].id)
        #expect(status?.level == .idle)
        #expect(status?.message.contains("idle") == true)
    }

    @Test
    func stopSimulationPublishesLatestIdleTransportStatus() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].transport = .tcp
        simulator.outputEndpoints[0].isEnabled = false
        simulator.startSimulation()

        simulator.stopSimulation()

        #expect(simulator.latestTransportStatus?.level == .idle)
        #expect(simulator.latestTransportStatus?.message.contains("idle") == true)
    }

    @Test
    func restartingTimedTcpSimulationKeepsTransmittingStateConsistent() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].transport = .tcp
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = true

        simulator.startSimulation()
        #expect(simulator.isTransmitting == true)

        simulator.stopSimulation()
        #expect(simulator.isTransmitting == false)
        #expect(simulator.latestTransportStatus?.level == .idle)

        simulator.startSimulation()
        #expect(simulator.isTransmitting == true)
        #expect(simulator.transportHistory.contains { $0.category == .lifecycle && $0.message == "Simulation started" })
    }

    @Test
    func timerOffThenOnDoesNotPretendToBeRunning() {
        let simulator = configuredSimulatorForDeterministicOutput()
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.startSimulation()

        #expect(simulator.isTransmitting == false)

        simulator.isTimerSelected = true

        #expect(simulator.isTransmitting == false)
        #expect(simulator.transportHistory.contains { $0.message == "Timer re-enabled" } == false)
    }
}

private func configuredSimulatorForDeterministicOutput() -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: isolatedDefaults())
    simulator.twd = SimulatedValue(type: .windDirection, center: 90, offset: 0)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 10, offset: 0)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0)
    simulator.depth = SimulatedValue(type: .depth, center: 12, offset: 0)
    simulator.seaTemp = SimulatedValue(type: .seaTemp, center: 18, offset: 0)
    simulator.gpsData = GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90)
    simulator.mwvReferenceMode = .relative
    return simulator
}

private func onlyEnabledSentence(_ keyPath: WritableKeyPath<SentenceToggleStates, Bool>) -> SentenceToggleStates {
    var toggles = SentenceToggleStates(
        shouldSendMWV: false,
        shouldSendMWD: false,
        shouldSendVPW: false,
        shouldSendHDG: false,
        shouldSendHDT: false,
        shouldSendROT: false,
        shouldSendRMC: false,
        shouldSendGGA: false,
        shouldSendVTG: false,
        shouldSendGLL: false,
        shouldSendGSA: false,
        shouldSendGSV: false,
        shouldSendZDA: false,
        shouldSendDBT: false,
        shouldSendDPT: false,
        shouldSendVHW: false,
        shouldSendVLW: false,
        shouldSendVBW: false,
        shouldSendMTW: false
    )
    toggles[keyPath: keyPath] = true
    return toggles
}

private func makeSnapshot(
    timestamp: Date,
    windDirectionTrue: Double? = 90,
    windSpeedTrue: Double? = 10,
    magneticHeading: Double? = 0,
    gyroHeading: Double? = 0,
    magneticVariation: Double = 0,
    boatSpeed: Double? = 0,
    gpsSignal: GPSSignalSnapshot? = nil
) -> SimulationSnapshot {
    SimulationSnapshot(
        timestamp: timestamp,
        windDirectionTrue: windDirectionTrue,
        windSpeedTrue: windSpeedTrue,
        magneticHeading: magneticHeading,
        gyroHeading: gyroHeading,
        magneticVariation: magneticVariation,
        compassDeviation: 0,
        boatSpeed: boatSpeed,
        depth: 12,
        seaTemperature: 18,
        gpsData: GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90),
        gpsSignal: gpsSignal ?? GPSSignalSnapshot(
            fixQuality: 1,
            fixMode: 3,
            selectionMode: "A",
            satellitesUsed: 8,
            hdop: 0.9,
            vdop: 1.1,
            pdop: 1.4,
            altitudeMeters: 14.2,
            geoidalSeparationMeters: 36.1,
            satellites: [
                GPSSatelliteSnapshot(prn: 1, elevation: 45, azimuth: 120, snr: 35, isUsedInFix: true),
                GPSSatelliteSnapshot(prn: 2, elevation: 50, azimuth: 180, snr: 38, isUsedInFix: true),
                GPSSatelliteSnapshot(prn: 3, elevation: 30, azimuth: 240, snr: 28, isUsedInFix: true),
                GPSSatelliteSnapshot(prn: 4, elevation: 20, azimuth: 300, snr: 22, isUsedInFix: true)
            ]
        ),
        turnRate: 0,
        logDistanceNm: 1.2,
        tripDistanceNm: 0.4
    )
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "MarineSimulatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "test-suite-name")
    return defaults
}

private func defaultsSuiteName(for defaults: UserDefaults) -> String {
    defaults.string(forKey: "test-suite-name") ?? ""
}

private func isValidNMEASentence(_ sentence: String) -> Bool {
    guard sentence.hasPrefix("$"),
          sentence.hasSuffix("\r\n"),
          let starIndex = sentence.firstIndex(of: "*")
    else {
        return false
    }

    let payload = sentence[sentence.index(after: sentence.startIndex)..<starIndex]
    let checksumStart = sentence.index(after: starIndex)
    let checksumEnd = sentence.index(checksumStart, offsetBy: 2, limitedBy: sentence.endIndex) ?? sentence.endIndex
    let providedChecksum = String(sentence[checksumStart..<checksumEnd])

    guard providedChecksum.count == 2 else {
        return false
    }

    let computedChecksum = payload.reduce(0) { partialResult, character in
        partialResult ^ Int(character.asciiValue ?? 0)
    }

    return providedChecksum.uppercased() == String(format: "%02X", computedChecksum)
}

private func makeLiveWeatherSnapshot() -> LiveWeatherSnapshot {
    LiveWeatherSnapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
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

private struct StubWeatherService: WeatherService {
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

private struct DelayedStubWeatherService: WeatherService {
    let snapshot: LiveWeatherSnapshot
    let delayNanoseconds: UInt64

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return LiveWeatherSnapshot(
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

private final class SequencedWeatherService: WeatherService {
    private var responses: [Result<LiveWeatherSnapshot, Error>]
    private var index = 0

    init(responses: [Result<LiveWeatherSnapshot, Error>]) {
        self.responses = responses
    }

    func fetchWeather(latitude: Double, longitude: Double, date: Date) async throws -> LiveWeatherSnapshot {
        let response = responses[min(index, responses.count - 1)]
        index += 1

        switch response {
        case .success(let snapshot):
            return LiveWeatherSnapshot(
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
        case .failure(let error):
            throw error
        }
    }
}
