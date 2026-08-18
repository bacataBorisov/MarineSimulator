import Foundation
import Testing
@testable import MarineSimulator

/// Locks tack target selection and heading apply after the `NMEASimulator+Tack` extract.
@Suite(.serialized)
struct TackRegressionTests {

    @Test
    func canExecuteTackRequiresAnemometerAndHeadingSource() {
        let simulator = makeTackSimulator()
        simulator.sensorToggles.hasAnemometer = false
        simulator.sensorToggles.hasGyro = true
        #expect(simulator.canExecuteTackManeuver == false)

        simulator.sensorToggles.hasAnemometer = true
        simulator.sensorToggles.hasGyro = false
        simulator.sensorToggles.hasCompass = false
        #expect(simulator.canExecuteTackManeuver == false)

        simulator.sensorToggles.hasCompass = true
        #expect(simulator.canExecuteTackManeuver)
    }

    @Test @MainActor
    func beginTackDoesNothingWithoutRequiredSensors() {
        let simulator = makeTackSimulator()
        simulator.sensorToggles.hasAnemometer = false
        simulator.beginTackManeuver()
        #expect(simulator.tackAnimationState == nil)
        #expect(simulator.isTackInProgress == false)
    }

    @Test @MainActor
    func beginTackTargetsOppositeCloseHauledHeading() {
        let simulator = makeTackSimulator()
        simulator.twd = SimulatedValue(type: .windDirection, center: 0, offset: 0, value: 0)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.heading = SimulatedValue(type: .magneticCompass, center: 325, offset: 0, value: 325)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 325, offset: 0, value: 325)

        simulator.beginTackManeuver()
        defer { simulator.tackAnimationTimer?.invalidate(); simulator.tackAnimationState = nil }

        let state = simulator.tackAnimationState
        #expect(state != nil)
        #expect(simulator.isTackInProgress)
        #expect(simulator.tackAnimationInProgress)
        #expect(simulator.tackAnimationTimer != nil)

        let optimal = simulator.boatProfile.optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: 12)
        let port = normalizeAngle(0 + optimal)
        #expect(abs(calculateShortestRotation(from: state?.toTrueHeading ?? 0, to: port)) < 0.6)
        #expect(abs(calculateShortestRotation(from: state?.fromTrueHeading ?? 0, to: 325)) < 8)
    }

    @Test
    func tackAnimationStateUsesSmoothstepAndCompletes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = NMEASimulator.TackAnimationState(
            startDate: start,
            duration: 10,
            fromTrueHeading: 10,
            toTrueHeading: 100
        )

        #expect(state.trueHeading(at: start) == 10)
        #expect(state.isComplete(at: start) == false)

        let mid = state.trueHeading(at: start.addingTimeInterval(5))
        #expect(abs(mid - 55) < 0.01)

        #expect(state.isComplete(at: start.addingTimeInterval(10)))
        #expect(state.trueHeading(at: start.addingTimeInterval(10)) == 100)
    }

    @Test
    func advanceTackAnimationLandsOnTargetAndClearsState() {
        let simulator = makeTackSimulator()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        simulator.tackAnimationState = NMEASimulator.TackAnimationState(
            startDate: start,
            duration: 8,
            fromTrueHeading: 40,
            toTrueHeading: 120
        )

        simulator.advanceTackAnimation(at: start)
        #expect(simulator.gyroHeading.value == 40)
        #expect(simulator.isTackInProgress)

        simulator.advanceTackAnimation(at: start.addingTimeInterval(8))
        #expect(simulator.gyroHeading.value == 120)
        #expect(simulator.tackAnimationState == nil)
        #expect(simulator.isTackInProgress == false)
        #expect(simulator.tackAnimationTimer == nil)
    }

    @Test
    func applySimulatedTrueHeadingWritesGyroAndMagneticWithVariation() {
        let simulator = makeTackSimulator()
        simulator.sensorToggles.hasGyro = true
        simulator.sensorToggles.hasCompass = true
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let variation = simulator.simulatedMagneticVariation(for: simulator.gpsData, at: date)

        simulator.applySimulatedTrueHeading(90, at: date)

        #expect(simulator.gyroHeading.value == 90)
        #expect(simulator.heading.value == normalizeAngle(90 - variation))
    }

    @Test
    func applySimulatedTrueHeadingSkipsDisabledHeadingSensors() {
        let simulator = makeTackSimulator()
        simulator.sensorToggles.hasGyro = false
        simulator.sensorToggles.hasCompass = true
        simulator.gyroHeading.value = 12
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        simulator.applySimulatedTrueHeading(200, at: date)

        #expect(simulator.gyroHeading.value == 12)
        #expect(simulator.heading.value != nil)
        #expect(simulator.heading.value != 12)
    }

    @Test
    func applySimulatedTrueHeadingUpdatesSnapshotWhileTransmitting() {
        let simulator = makeTackSimulator()
        simulator.isTransmitting = true
        simulator.latestSnapshot = SimulationSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            windDirectionTrue: 0,
            windSpeedTrue: 12,
            magneticHeading: 10,
            gyroHeading: 10,
            magneticVariation: 0,
            compassDeviation: 0,
            boatSpeed: 6,
            depth: 12,
            seaTemperature: 18,
            airTemperature: 22,
            relativeHumidity: 65,
            airPressure: 1013,
            gpsData: simulator.gpsData,
            gpsSignal: GPSSignalSnapshot(
                fixQuality: 1,
                fixMode: 3,
                selectionMode: "A",
                satellitesUsed: 8,
                hdop: 0.9,
                vdop: 1.1,
                pdop: 1.4,
                altitudeMeters: 14,
                geoidalSeparationMeters: 36,
                satellites: []
            ),
            turnRate: 0,
            logDistanceNm: 1,
            tripDistanceNm: 0.2,
            navigationTarget: nil
        )
        let date = Date(timeIntervalSince1970: 1_700_000_100)

        simulator.applySimulatedTrueHeading(45, at: date)

        #expect(simulator.latestSnapshot?.timestamp == date)
        #expect(simulator.latestSnapshot?.gyroHeading == 45)
        #expect(simulator.latestSnapshot?.boatSpeed == 6)
    }
}

private func makeTackSimulator() -> NMEASimulator {
    let suiteName = "MarineSimulatorTests.Tack.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasGyro = true
    simulator.twd = SimulatedValue(type: .windDirection, center: 0, offset: 0, value: 0)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: 325, offset: 0, value: 325)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 325, offset: 0, value: 325)
    return simulator
}
