import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct ManeuverCommandTests {

    @Test
    func tackAndGybeFinishOnTheMirroredHeading() {
        #expect(SimulationEngine.currentTack(trueHeading: 45, trueWindDirection: 0) == .port)
        #expect(SimulationEngine.currentTack(trueHeading: 315, trueWindDirection: 0) == .starboard)
        #expect(SimulationEngine.currentTack(trueHeading: 0, trueWindDirection: 0) == nil)
        #expect(SimulationEngine.currentTack(trueHeading: 180, trueWindDirection: 0) == nil)

        let upwind = [
            (ManeuverCommand.tack(.starboard), 45.0, -90.0),
            (.gybe(.starboard), 45.0, 270.0),
            (.tack(.port), 315.0, 90.0),
            (.gybe(.port), 315.0, -270.0)
        ]
        let downwind = [
            (ManeuverCommand.tack(.starboard), 120.0, -240.0),
            (.gybe(.starboard), 120.0, 120.0),
            (.tack(.port), 240.0, 240.0),
            (.gybe(.port), 240.0, -120.0)
        ]
        for item in upwind + downwind {
            let plan = SimulationEngine.maneuverPlan(command: item.0, fromHeading: item.1, trueWindDirection: 0)
            let target = normalizeAngle(2 * 0 - item.1)
            #expect(plan?.turnDelta == item.2)
            #expect(abs(calculateShortestRotation(from: plan?.target ?? -1, to: target)) < 0.001)
            let windAxis = item.0.kind == .tack ? 0.0 : 180.0
            let otherAxis = item.0.kind == .tack ? 180.0 : 0.0
            #expect(SimulationEngine.arcContains(start: item.1, delta: plan?.turnDelta ?? 0, angle: windAxis))
            #expect(SimulationEngine.arcContains(start: item.1, delta: plan?.turnDelta ?? 0, angle: otherAxis) == false)
        }

        #expect(SimulationEngine.maneuverPlan(command: .tack(.port), fromHeading: 45, trueWindDirection: 0) == nil)
        #expect(SimulationEngine.maneuverPlan(command: .gybe(.port), fromHeading: 45, trueWindDirection: 0) == nil)
        #expect(SimulationEngine.maneuverPlan(command: .tack(.starboard), fromHeading: 0, trueWindDirection: 0) == nil)
    }

    @Test @MainActor
    func explicitCommandsReachTheRequestedSideAndIgnoreDuplicates() {
        let simulator = makeManeuverSimulator()
        simulator.beginManeuver(.tack(.port))
        let maneuver = simulator.activeManeuver
        #expect(maneuver?.side == .port)
        #expect(maneuver?.kind == .tack)
        #expect(abs(calculateShortestRotation(from: maneuver?.toTrueHeading ?? 0, to: 270)) < 0.2)
        #expect(maneuver?.turnDelta == 180)
        #expect(simulator.isTackInProgress)
        #expect(simulator.vesselObservation.maneuverPhase == .inProgress)
        #expect(simulator.tackAnimationTimer == nil)

        let started = maneuver?.startedAt
        simulator.beginManeuver(.tack(.port))
        #expect(simulator.activeManeuver?.startedAt == started)

        let speed = simulator.speed.value
        simulator.beginManeuver(.gybe(.starboard))
        #expect(simulator.speed.value == speed)
        #expect(simulator.activeManeuver?.kind == .tack)
        #expect(simulator.activeManeuver?.startedAt == started)

        simulator.beginManeuver(.gybe(.port))
        #expect(simulator.speed.value == speed)
        #expect(simulator.activeManeuver?.kind == .gybe)
        #expect(simulator.activeManeuver?.side == .port)
        #expect(simulator.activeManeuver?.startedAt != started)
        #expect(simulator.activeManeuver?.turnDelta == -180)
        #expect(abs(calculateShortestRotation(from: simulator.activeManeuver?.toTrueHeading ?? 0, to: 270)) < 0.2)
    }

    @Test @MainActor
    func commandOnTheCurrentHeadingDoesNothing() {
        let simulator = makeManeuverSimulator()
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 270, offset: 0, value: 270)
        simulator.beginManeuver(.tack(.port))
        #expect(simulator.activeManeuver == nil)
        simulator.beginManeuver(.gybe(.port))
        #expect(simulator.activeManeuver == nil)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 180, offset: 0, value: 180)
        simulator.beginManeuver(.tack(.starboard))
        #expect(simulator.isTackInProgress == false)
    }

    @Test
    func longGybeDoesNotShortcutAndWindDoesNotRetarget() {
        var rig = ManeuverRig()
        let start = rig.time
        let plan = SimulationEngine.maneuverPlan(command: .gybe(.starboard), fromHeading: 45, trueWindDirection: 0)
        rig.state.twd.value = 0
        rig.state.twd.centerValue = 0
        rig.state.gyroHeading.value = 45
        rig.state.gyroHeading.centerValue = 45
        rig.state.vesselTruth.trueHeading = 45
        rig.state.activeManeuver = ActiveManeuver(
            kind: .gybe,
            side: .starboard,
            startedAt: start,
            duration: 10,
            fromTrueHeading: 45,
            toTrueHeading: plan?.target ?? 0,
            trueWindDirection: 0,
            turnDelta: plan?.turnDelta ?? 0,
            drivesHeading: true
        )
        var signed = 0.0
        var previous = 45.0
        for step in 0...10 {
            if step == 3 {
                rig.state.twd.value = 30
                rig.state.twd.centerValue = 30
            }
            let snapshot = tick(&rig, at: start.addingTimeInterval(Double(step)))
            let truth = rig.state.vesselTruth.trueHeading
            let gyro = snapshot.gyroHeading ?? -1
            #expect(abs(calculateShortestRotation(from: truth, to: gyro)) < 0.001)
            #expect(NMEANumericFormatting.format(truth, fractionDigits: 1) == NMEANumericFormatting.format(gyro, fractionDigits: 1))
            if step > 0 {
                let delta = calculateShortestRotation(from: previous, to: truth)
                #expect(delta >= -0.1)
                signed += delta
            }
            previous = truth
        }
        #expect(abs(signed - 270) < 0.5)
        #expect(abs(calculateShortestRotation(from: previous, to: 315)) < 0.05)
        #expect(rig.state.activeManeuver == nil)
    }

    @Test
    func windChangeDoesNotMoveTheCapturedTarget() {
        var rig = ManeuverRig()
        let start = rig.time
        rig.state.activeManeuver = ActiveManeuver(
            kind: .tack,
            side: .port,
            startedAt: start,
            duration: 20,
            fromTrueHeading: 140,
            toTrueHeading: 220,
            trueWindDirection: 180,
            turnDelta: 80,
            drivesHeading: true
        )
        _ = tick(&rig, at: start.addingTimeInterval(1))
        let captured = rig.state.activeManeuver
        rig.state.twd.value = 210
        rig.state.twd.centerValue = 210
        _ = tick(&rig, at: start.addingTimeInterval(2))
        #expect(rig.state.activeManeuver?.toTrueHeading == captured?.toTrueHeading)
        #expect(rig.state.activeManeuver?.trueWindDirection == 180)
        #expect(rig.state.activeManeuver?.turnDelta == 80)
    }

    @Test @MainActor
    func manualHeadingInterruptsIntoRecovery() {
        let simulator = makeManeuverSimulator()
        simulator.beginManeuver(.tack(.port))
        #expect(simulator.isTackInProgress)
        simulator.interruptManeuver(withTrueHeading: 10)
        #expect(simulator.isTackInProgress == false)
        #expect(simulator.gyroHeading.value == 10)
        #expect(simulator.vesselObservation.maneuverPhase == .recovery)

        var state = SimulationState(from: simulator)
        state.lastSensorEvolutionDate = Date()
        state.lastSimulationTickDate = Date()
        let config = simulator.captureSimulationConfig()
        _ = SimulationEngine.tickSimulation(
            state: &state,
            config: config,
            at: Date().addingTimeInterval(0.05),
            liveWeatherValueGenerator: { base, _, _, _ in base }
        )
        #expect(abs((state.gyroHeading.value ?? 0) - 10) < 0.2)
        #expect(abs((state.vesselTruth.trueHeading) - 10) < 0.2)
    }

    @Test
    func drivenHeadingMatchesTruthAndDoesNotReverse() {
        var rig = ManeuverRig()
        let start = rig.time
        rig.state.activeManeuver = ActiveManeuver(
            kind: .gybe,
            side: .port,
            startedAt: start,
            duration: 10,
            fromTrueHeading: 350,
            toTrueHeading: 40,
            trueWindDirection: 0,
            turnDelta: 50,
            drivesHeading: true
        )
        var samples: [Double] = []
        for step in 0...10 {
            let snapshot = tick(&rig, at: start.addingTimeInterval(Double(step)))
            let truth = rig.state.vesselTruth.trueHeading
            let gyro = snapshot.gyroHeading ?? -1
            samples.append(truth)
            #expect(abs(calculateShortestRotation(from: truth, to: gyro)) < 0.001)
            let formatted = NMEANumericFormatting.format(truth, fractionDigits: 1)
            #expect(NMEANumericFormatting.format(gyro, fractionDigits: 1) == formatted)
        }
        for pair in zip(samples, samples.dropFirst()) {
            let step = calculateShortestRotation(from: pair.0, to: pair.1)
            #expect(step >= -0.1)
        }
        #expect(samples.last == 40)
    }

    @Test @MainActor
    func customDurationIsStoredAndUsed() throws {
        let simulator = makeManeuverSimulator()
        simulator.maneuverSettings.usesTackDuration = true
        simulator.maneuverSettings.tackDurationSeconds = 12
        simulator.maneuverSettings.tackSpeedRetention = 0.7
        let decoded = try JSONDecoder().decode(
            SimulatorSettings.self,
            from: JSONEncoder().encode(simulator.makeSettingsSnapshotForExport())
        )
        #expect(decoded.maneuverSettings.usesTackDuration)
        #expect(decoded.maneuverSettings.tackDurationSeconds == 12)
        #expect(decoded.maneuverSettings.tackSpeedRetention == 0.7)
        simulator.beginManeuver(.tack(.port))
        #expect(simulator.activeManeuver?.duration == 12)
    }

    @Test @MainActor
    func anemometerFollowsLiveHeadingWhileTheSnapshotStaysBehind() {
        let simulator = makeManeuverSimulator()
        simulator.isTransmitting = true
        simulator.latestSnapshot = SimulationSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            windDirectionTrue: 180,
            windSpeedTrue: 12,
            magneticHeading: 90,
            gyroHeading: 90,
            magneticVariation: 0,
            compassDeviation: 0,
            boatSpeed: 0,
            depth: nil,
            seaTemperature: nil,
            airTemperature: nil,
            relativeHumidity: nil,
            airPressure: nil,
            gpsData: simulator.gpsData,
            gpsSignal: GPSSignalSnapshot(
                fixQuality: 1, fixMode: 3, selectionMode: "A", satellitesUsed: 8,
                hdop: 1, vdop: 1, pdop: 1, altitudeMeters: 0, geoidalSeparationMeters: 0, satellites: []
            ),
            turnRate: 0,
            logDistanceNm: 0,
            tripDistanceNm: 0,
            navigationTarget: nil
        )
        simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
        simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
        simulator.speed = SimulatedValue(type: .speedLog, center: 0, offset: 0, value: 0)
        simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 120, offset: 0, value: 120)
        simulator.tackAnimationState = NMEASimulator.TackAnimationState(
            startDate: Date(),
            duration: 10,
            fromTrueHeading: 90,
            toTrueHeading: 140
        )

        let live = simulator.liveManeuverWindAngles()
        #expect(live != nil)
        #expect(abs(calculateShortestRotation(from: live?.trueAngle ?? 0, to: 60)) < 0.01)
        #expect(abs((simulator.calculatedTWA ?? 0) - 90) < 0.01)
    }

    @Test
    func manualAndFromWindStayOnCourseWithoutAManeuver() {
        var manual = ManeuverRig(mode: .manual)
        _ = tick(&manual, at: manual.time)
        #expect(manual.state.speed.value == 6)
        #expect(manual.state.vesselObservation.maneuverPhase == .idle)

        var estimated = ManeuverRig(mode: .estimated)
        _ = tick(&estimated, at: estimated.time)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs((estimated.state.vesselTruth.speedThroughWaterKnots ?? 0) - polar) < 0.000_001)
        #expect(estimated.state.activeManeuver == nil)
    }
}

private struct ManeuverRig {
    var state: SimulationState
    var config: SimulationConfig
    var time = Date(timeIntervalSince1970: 1_800_004_000)

    init(mode: BoatSpeedMode = .estimated) {
        let simulator = makeManeuverSimulator()
        simulator.boatSpeedMode = mode
        state = SimulationState(from: simulator)
        state.lastSensorEvolutionDate = time
        config = simulator.captureSimulationConfig()
    }
}

private func tick(_ rig: inout ManeuverRig, at time: Date) -> SimulationSnapshot {
    SimulationEngine.tickSimulation(
        state: &rig.state,
        config: rig.config,
        at: time,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
}

private func makeManeuverSimulator() -> NMEASimulator {
    let suite = "ManeuverCommand.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.boatSpeedMode = .estimated
    simulator.boatProfile = .beneteauFirst407
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasGPS = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.sensorToggles.hasAnemometer = true
    let time = Date(timeIntervalSince1970: 1_800_004_000)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.speed = SimulatedValue(type: .speedLog, center: 6, offset: 0, value: 6)
    return simulator
}
