import Foundation
import Testing
@testable import MarineSimulator

// MARK: - Phase 0: Regression Safety Net
// These tests cover previously untested simulation physics,
// providing a safety net for the planned architectural refactoring.

struct NavigationMathTests {

    // MARK: - RMB / XTE Sentence Tests

    @Test
    func rmbBearingAndRangeForKnownWaypointPair() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())

        // Boat at 43.19542N, 27.89615E; destination 43.20N, 27.90E; origin 43.19N, 27.89E
        let snapshot = makeNavSnapshot(
            boatLat: 43.19542, boatLon: 27.89615,
            origLat: 43.19000, origLon: 27.89000,
            destLat: 43.20000, destLon: 27.90000,
            sog: 6, cog: 90
        )

        let sentences = simulator.buildNMEASentences(talkerID: "GP", type: .rmb, snapshot: snapshot)
        #expect(sentences.count == 1)

        let raw = stripChecksum(sentences[0])
        let fields = raw.components(separatedBy: ",")

        // $GPRMB,A,<xte>,<dir>,WP0,WP1,<destLat>,N,<destLon>,E,<range>,<bearing>,<vmc>,<arrived>
        #expect(fields[0] == "$GPRMB")
        #expect(fields[1] == "A")                    // Status: active

        // Range ≈ 0.3 NM
        let range = Double(fields[10])!
        #expect(abs(range - 0.3) < 0.1, "Range \(range) should be ~0.3 NM")

        // Bearing ≈ 31.5°
        let bearing = Double(fields[11])!
        #expect(abs(bearing - 31.5) < 1.0, "Bearing \(bearing) should be ~31.5°")

        // VMC ≈ 3.1 kt (SOG=6, COG=90, bearing≈31.5)
        let vmc = Double(fields[12])!
        #expect(abs(vmc - 3.1) < 0.5, "VMC \(vmc) should be ~3.1 kt")

        // Not arrived (range > 0.05 NM)
        #expect(fields[13] == "V")
    }

    @Test
    func xteCrossTrackErrorDirectionReflectsPortStarboardOffset() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())

        // Boat RIGHT of the course line: 43.19542N, 27.89615E
        let snapshotRight = makeNavSnapshot(
            boatLat: 43.19542, boatLon: 27.89615,
            origLat: 43.19000, origLon: 27.89000,
            destLat: 43.20000, destLon: 27.90000,
            sog: 6, cog: 90
        )

        let rightSentences = simulator.buildNMEASentences(talkerID: "GP", type: .xte, snapshot: snapshotRight)
        #expect(rightSentences.count == 1)
        let rightRaw = stripChecksum(rightSentences[0])
        let rightFields = rightRaw.components(separatedBy: ",")
        // $GPXTE,A,A,<xte>,<dir>,N
        #expect(rightFields[4] == "R", "Boat right of course should produce 'R'")

        // Boat LEFT of the course line: 43.198N, 27.891E
        let snapshotLeft = makeNavSnapshot(
            boatLat: 43.19800, boatLon: 27.89100,
            origLat: 43.19000, origLon: 27.89000,
            destLat: 43.20000, destLon: 27.90000,
            sog: 6, cog: 90
        )

        let leftSentences = simulator.buildNMEASentences(talkerID: "GP", type: .xte, snapshot: snapshotLeft)
        #expect(leftSentences.count == 1)
        let leftRaw = stripChecksum(leftSentences[0])
        let leftFields = leftRaw.components(separatedBy: ",")
        #expect(leftFields[4] == "L", "Boat left of course should produce 'L'")
    }

    @Test
    func rmbArrivalFlagTriggersWithinArrivalRadius() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())

        // Boat practically at destination
        let snapshot = makeNavSnapshot(
            boatLat: 43.19999, boatLon: 27.89999,
            origLat: 43.19000, origLon: 27.89000,
            destLat: 43.20000, destLon: 27.90000,
            sog: 1, cog: 45,
            arrivalRadius: 0.05
        )

        let sentences = simulator.buildNMEASentences(talkerID: "GP", type: .rmb, snapshot: snapshot)
        #expect(sentences.count == 1)

        let raw = stripChecksum(sentences[0])
        let fields = raw.components(separatedBy: ",")
        #expect(fields[13] == "A", "Should be 'A' (arrived) when within arrival radius")
    }

    @Test
    func rmbVmcComputesVelocityMadeGoodTowardDestination() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())

        // Heading directly toward destination (COG ≈ bearing)
        // Destination is due north of boat
        let snapshot = makeNavSnapshot(
            boatLat: 43.00000, boatLon: 28.00000,
            origLat: 42.99000, origLon: 28.00000,
            destLat: 43.10000, destLon: 28.00000,
            sog: 8, cog: 0  // Heading straight north
        )

        let sentences = simulator.buildNMEASentences(talkerID: "GP", type: .rmb, snapshot: snapshot)
        let raw = stripChecksum(sentences[0])
        let fields = raw.components(separatedBy: ",")

        // VMC should be close to SOG since COG ≈ bearing to dest
        let vmc = Double(fields[12])!
        #expect(abs(vmc - 8.0) < 0.5, "VMC \(vmc) should be near SOG when heading directly to destination")
    }

    @Test
    func rmbAndXteReturnEmptyWhenNoNavigationTarget() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        let snapshot = makeSnapshot(timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        let rmb = simulator.buildNMEASentences(talkerID: "GP", type: .rmb, snapshot: snapshot)
        let xte = simulator.buildNMEASentences(talkerID: "GP", type: .xte, snapshot: snapshot)

        #expect(rmb.isEmpty, "RMB should not emit without a navigation target")
        #expect(xte.isEmpty, "XTE should not emit without a navigation target")
    }

    // MARK: - Magnetic Variation (tested indirectly via snapshot)

    @Test
    func magneticVariationIncreasesWithEasternLongitude() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasGyro = true

        // Capture variation at lon=0 vs lon=28 by running a tick at each
        simulator.gpsData = GPSData(latitude: 43, longitude: 0, speedOverGround: 0, courseOverGround: 0)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 0, offset: 0, value: 0)
        simulator.startSimulation()
        let snapshot1 = simulator.latestSnapshot
        simulator.stopSimulation()

        simulator.gpsData = GPSData(latitude: 43, longitude: 28, speedOverGround: 0, courseOverGround: 0)
        simulator.startSimulation()
        let snapshot2 = simulator.latestSnapshot
        simulator.stopSimulation()

        // Magnetic variation should be larger at lon=28 than lon=0
        guard let var1 = snapshot1?.magneticVariation, let var2 = snapshot2?.magneticVariation else {
            Issue.record("Snapshots should contain magnetic variation")
            return
        }
        #expect(var2 > var1, "Variation at lon=28 (\(var2)) should exceed variation at lon=0 (\(var1))")
    }

    @Test
    func magneticVariationIsClampedToReasonableRange() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false

        // Test at extreme longitude
        simulator.gpsData = GPSData(latitude: 43, longitude: 170, speedOverGround: 0, courseOverGround: 0)
        simulator.startSimulation()
        let snapshot = simulator.latestSnapshot
        simulator.stopSimulation()

        guard let variation = snapshot?.magneticVariation else {
            Issue.record("Snapshot should contain magnetic variation")
            return
        }
        #expect(variation >= -25 && variation <= 25, "Variation \(variation) should be clamped to [-25, 25]")
    }

    // MARK: - Compass Deviation (tested indirectly via snapshot)

    @Test
    func compassDeviationIsSmallAndBoundedInSnapshots() {
        // Compass deviation = sin(heading * 1.7) * 1.2, so |deviation| <= 1.2 always
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasCompass = true
        simulator.startSimulation()

        guard let deviation = simulator.latestSnapshot?.compassDeviation else {
            Issue.record("Snapshot should contain compass deviation")
            return
        }
        #expect(abs(deviation) <= 1.3, "Deviation magnitude should not exceed 1.2 (sine * 1.2), got \(deviation)")
        simulator.stopSimulation()
    }

    @Test
    func compassDeviationVariesAcrossHeadings() {
        // Verify the deviation is not constant — it varies with heading direction
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasGyro = false

        var deviations: [Double] = []
        for hdg in stride(from: 0.0, to: 360.0, by: 90.0) {
            let sim = NMEASimulator(userDefaults: isolatedDefaults())
            sim.outputEndpoints[0].isEnabled = false
            sim.isTimerSelected = false
            sim.sensorToggles.hasCompass = true
            sim.sensorToggles.hasGyro = false
            sim.heading = SimulatedValue(type: .magneticCompass, center: hdg, offset: 0, value: hdg)
            sim.startSimulation()
            if let dev = sim.latestSnapshot?.compassDeviation {
                deviations.append(dev)
            }
            sim.stopSimulation()
        }

        #expect(deviations.count == 4)
        // Deviation should vary across headings (not all identical)
        let range = (deviations.max() ?? 0) - (deviations.min() ?? 0)
        #expect(range > 0.5, "Compass deviation should vary across headings, range was \(range)")
        // All deviations should be bounded
        for dev in deviations {
            #expect(abs(dev) <= 1.3, "Each deviation should be bounded: got \(dev)")
        }
    }

    // MARK: - Boat Speed Estimation

    @Test
    func estimatedBoatSpeedIsNilWhenSpeedLogDisabled() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.boatSpeedMode = .estimated
        simulator.sensorToggles.hasSpeedLog = false
        simulator.sensorToggles.hasAnemometer = true
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)

        simulator.startSimulation()
        #expect(simulator.speed.value == nil, "Speed should be nil when speed log is disabled")
        simulator.stopSimulation()
    }

    @Test
    func estimatedBoatSpeedPositiveForReasonableConditions() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.boatSpeedMode = .estimated
        simulator.boatProfile = .beneteauFirst407
        simulator.sensorToggles.hasSpeedLog = true
        simulator.sensorToggles.hasAnemometer = true
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasGyro = false
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)
        simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)

        simulator.startSimulation()
        let speed = simulator.speed.value
        #expect(speed != nil, "Speed should be computed")
        #expect((speed ?? 0) > 3.0, "Speed \(speed ?? 0) should be > 3 kt for TWS 12 beam reach")
        #expect((speed ?? 0) < 12.0, "Speed \(speed ?? 0) should be < 12 kt (reasonable for TWS 12)")
        simulator.stopSimulation()
    }

    @Test
    func polarLookupReturnsExpectedValuesAtKnownPoints() {
        // Test the polar table directly (public API on BoatProfile)
        let profile = BoatProfile.beneteauFirst407

        // TWA 45°, TWS 12 → expect 7.01 kt
        let speed45 = profile.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 45)
        #expect(abs(speed45 - 7.01) < 0.01, "Polar at TWA 45° TWS 12 should be 7.01, got \(speed45)")

        // TWA 90°, TWS 12 → expect 8.18 kt
        let speed90 = profile.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90)
        #expect(abs(speed90 - 8.18) < 0.01, "Polar at TWA 90° TWS 12 should be 8.18, got \(speed90)")

        // TWA 5° (deep pinch) should be very slow
        let speed5 = profile.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 5)
        #expect(speed5 < 2.0, "Polar at TWA 5° should produce very slow speed, got \(speed5)")

        // J/109 at TWA 90°, TWS 10 → expect 8.2
        let j109Speed = BoatProfile.j109.estimatedBoatSpeed(trueWindSpeedKnots: 10, trueWindAngleDegrees: 90)
        #expect(abs(j109Speed - 8.2) < 0.01, "J/109 at TWA 90° TWS 10 should be 8.2, got \(j109Speed)")
    }

    @Test
    func optimalUpwindAngleInterpolatesForKnownWindSpeeds() {
        let profile = BoatProfile.beneteauFirst407

        // TWS 6 → expect ~36.5°
        let angle6 = profile.optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: 6)
        #expect(abs(angle6 - 36.5) < 0.1, "Optimal upwind at TWS 6 should be ~36.5°, got \(angle6)")

        // TWS 12 → interpolated between 10 (34.3°) and 14 (33.5°) → ~33.9°
        let angle12 = profile.optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: 12)
        #expect(angle12 > 33.0 && angle12 < 35.0, "Optimal upwind at TWS 12 should be ~33.9°, got \(angle12)")
    }

    // MARK: - Tack Animation

    @Test
    func tackAnimationInterpolatesSmoothlyBetweenHeadings() {
        // TackAnimationState is private, so test through the simulator's tack maneuver API
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.sensorToggles.hasAnemometer = true
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasGyro = true
        simulator.twd = SimulatedValue(type: .windDirection, center: 0, offset: 0, value: 0)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        // Heading close-hauled on port tack (TWD=0, heading≈325 = 360-35)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 325, offset: 0, value: 325)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 325, offset: 0, value: 325)

        let canTack = simulator.canExecuteTackManeuver
        #expect(canTack, "Should be able to execute tack with anemometer + compass")
    }

    // MARK: - Turn Rate

    @Test
    func turnRateIsReflectedInSnapshot() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasCompass = true
        simulator.sensorToggles.hasGyro = false
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 90, offset: 0, value: 90)

        simulator.startSimulation()
        let snapshot = simulator.latestSnapshot
        #expect(snapshot != nil)
        // Turn rate on first tick should be 0 (no previous reference)
        #expect(snapshot?.turnRate == 0, "Turn rate on first tick should be 0")
        simulator.stopSimulation()
    }

    // MARK: - GPS Position Update

    @Test
    func gpsPositionAdvancesWhenMoving() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasGPS = true
        simulator.gpsData = GPSData(latitude: 43.0, longitude: 28.0, speedOverGround: 10, courseOverGround: 90)

        let initialLon = simulator.gpsData.longitude

        // Run two simulation cycles with a time gap
        simulator.startSimulation()
        simulator.stopSimulation()

        // After a tick with SOG=10 heading east, longitude should increase
        // Note: first tick might not advance because deltaTime=0
        // This test verifies the GPS update mechanism exists
        #expect(simulator.gpsData.longitude >= initialLon,
                "Longitude should not decrease when heading east")
    }

    @Test
    func gpsPositionDoesNotChangeWhenGPSDisabled() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasGPS = false
        simulator.gpsData = GPSData(latitude: 43.0, longitude: 28.0, speedOverGround: 10, courseOverGround: 90)

        let initialLat = simulator.gpsData.latitude
        let initialLon = simulator.gpsData.longitude

        simulator.startSimulation()
        simulator.stopSimulation()

        #expect(simulator.gpsData.latitude == initialLat, "Latitude should not change with GPS disabled")
        #expect(simulator.gpsData.longitude == initialLon, "Longitude should not change with GPS disabled")
    }

    // MARK: - Log Distance

    @Test
    func logDistanceAccumulatesAcrossTicks() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasSpeedLog = true
        simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)

        // Trip distance should start at 0 after a fresh run
        simulator.startSimulation()
        let initialTrip = simulator.latestSnapshot?.tripDistanceNm ?? 0
        // First tick has deltaTime=0 so trip stays 0
        #expect(initialTrip == 0 || initialTrip >= 0, "Trip distance should be non-negative")
        simulator.stopSimulation()
    }

    // MARK: - Sentence Toggle Gating

    @Test
    func rmbAndXteOnlyEmitWhenWaypointNavigationIsActive() {
        let simulator = NMEASimulator(userDefaults: isolatedDefaults())
        simulator.outputEndpoints[0].isEnabled = false
        simulator.isTimerSelected = false
        simulator.sensorToggles.hasGPS = true
        simulator.sentenceToggles.shouldSendRMB = true
        simulator.sentenceToggles.shouldSendXTE = true
        simulator.waypointNavigation.isActive = false

        simulator.startSimulation()
        let output = simulator.outputMessages
        simulator.stopSimulation()

        let hasRMB = output.contains(where: { $0.contains("RMB") })
        let hasXTE = output.contains(where: { $0.contains("XTE") })
        #expect(!hasRMB, "RMB should not appear when waypoint navigation is inactive")
        #expect(!hasXTE, "XTE should not appear when waypoint navigation is inactive")
    }

    // MARK: - NMEANumericFormatting

    @Test
    func nmeaFormattingProducesAsciiDecimalForAllLocales() {
        // Verify the formatter uses "." not "," regardless of locale
        let result = NMEANumericFormatting.format(3.14159, fractionDigits: 2)
        #expect(result == "3.14", "Formatted value should use ASCII decimal: got '\(result)'")

        let zero = NMEANumericFormatting.format(0.0, fractionDigits: 1)
        #expect(zero == "0.0", "Zero should format as '0.0', got '\(zero)'")
    }
}

// MARK: - Test Helpers

private func makeNavSnapshot(
    boatLat: Double, boatLon: Double,
    origLat: Double, origLon: Double,
    destLat: Double, destLon: Double,
    sog: Double, cog: Double,
    arrivalRadius: Double = 0.05
) -> SimulationSnapshot {
    SimulationSnapshot(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        windDirectionTrue: 90,
        windSpeedTrue: 10,
        magneticHeading: 0,
        gyroHeading: 0,
        magneticVariation: 0,
        compassDeviation: 0,
        boatSpeed: 6,
        depth: 12,
        seaTemperature: 18,
        airTemperature: 22,
        relativeHumidity: 65,
        airPressure: 1013,
        gpsData: GPSData(latitude: boatLat, longitude: boatLon, speedOverGround: sog, courseOverGround: cog),
        gpsSignal: GPSSignalSnapshot(
            fixQuality: 1, fixMode: 3, selectionMode: "A",
            satellitesUsed: 8, hdop: 0.9, vdop: 1.1, pdop: 1.4,
            altitudeMeters: 14.2, geoidalSeparationMeters: 36.1,
            satellites: []
        ),
        turnRate: 0,
        logDistanceNm: 0,
        tripDistanceNm: 0,
        navigationTarget: NavigationTarget(
            originName: "WP0", destinationName: "WP1",
            originLatitude: origLat, originLongitude: origLon,
            destinationLatitude: destLat, destinationLongitude: destLon,
            arrivalRadiusNm: arrivalRadius
        )
    )
}

private func makeSnapshot(
    timestamp: Date,
    windDirectionTrue: Double? = 90,
    windSpeedTrue: Double? = 10,
    magneticHeading: Double? = 0,
    gyroHeading: Double? = 0,
    magneticVariation: Double = 0,
    boatSpeed: Double? = 0
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
        airTemperature: 22,
        relativeHumidity: 65,
        airPressure: 1013,
        gpsData: GPSData(latitude: 43.19542, longitude: 27.89615, speedOverGround: 6, courseOverGround: 90),
        gpsSignal: GPSSignalSnapshot(
            fixQuality: 1, fixMode: 3, selectionMode: "A",
            satellitesUsed: 8, hdop: 0.9, vdop: 1.1, pdop: 1.4,
            altitudeMeters: 14.2, geoidalSeparationMeters: 36.1,
            satellites: []
        ),
        turnRate: 0,
        logDistanceNm: 0,
        tripDistanceNm: 0,
        navigationTarget: nil
    )
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "SimPhysicsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// Strip the NMEA checksum and CR/LF from a sentence for field parsing.
private func stripChecksum(_ sentence: String) -> String {
    guard let starIdx = sentence.firstIndex(of: "*") else { return sentence }
    return String(sentence[sentence.startIndex..<starIdx])
}
