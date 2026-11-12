import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct SailingStateTests {

    @Test
    func eligibilityFollowsTheSimulatorMatrix() {
        let profile = SailingProfile.extasy
        let cases: [(Double, PointOfSail, Bool, Bool)] = [
            (10, .noGo, false, false),
            (29.9, .noGo, false, false),
            (30, .closeHauled, true, false),
            (45, .closeHauled, true, false),
            (60, .closeReach, true, true),
            (70, .closeReach, true, true),
            (80, .beamReach, true, true),
            (90, .beamReach, true, true),
            (100, .broadReach, false, true),
            (120, .broadReach, false, true),
            (150, .running, false, true),
            (170, .running, false, true)
        ]
        for item in cases {
            let state = profile.resolve(trueHeading: item.0, trueWindDirection: 0, trueWindSpeedKnots: 12)
            #expect(state.pointOfSail == item.1)
            #expect(state.pointOfSailIsSimulatorDefined)
            let tackAllowed = profile.rejectionReason(for: .tack(.starboard), trueHeading: item.0, trueWindDirection: 0, trueWindSpeedKnots: 12) == nil
            let gybeAllowed = profile.rejectionReason(for: .gybe(.starboard), trueHeading: item.0, trueWindDirection: 0, trueWindSpeedKnots: 12) == nil
            #expect(tackAllowed == item.2)
            #expect(gybeAllowed == item.3)
        }
    }

    @Test
    func farrOptimaInterpolateInsideTheTableAndStayUnavailableOutside() {
        let profile = SailingProfile.extasy
        #expect(profile.optimalUpwindTrueWindAngle(trueWindSpeedKnots: 6) == 45.2)
        #expect(profile.optimalUpwindTrueWindAngle(trueWindSpeedKnots: 12) == 40.4)
        #expect(abs((profile.optimalUpwindTrueWindAngle(trueWindSpeedKnots: 9) ?? -1) - 42.5) < 0.001)
        #expect(profile.optimalDownwindTrueWindAngle(trueWindSpeedKnots: 12) == 155.4)
        #expect(abs((profile.optimalDownwindTrueWindAngle(trueWindSpeedKnots: 9) ?? -1) - 148.1) < 0.001)
        #expect(profile.optimalUpwindTrueWindAngle(trueWindSpeedKnots: 3) == nil)
        #expect(profile.optimalDownwindTrueWindAngle(trueWindSpeedKnots: 31) == nil)
    }

    @Test
    func farrSailCombinationStaysIndependentOfPointOfSail() {
        let profile = SailingProfile.extasy
        #expect(profile.sailCombination(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) == .up)
        #expect(profile.sailCombination(trueWindSpeedKnots: 12, trueWindAngleDegrees: 100) == .down)
        #expect(profile.sailCombination(trueWindSpeedKnots: 12, trueWindAngleDegrees: 95) == nil)
        #expect(profile.sailCombination(trueWindSpeedKnots: 5, trueWindAngleDegrees: 80) == .up)
        #expect(profile.sailCombination(trueWindSpeedKnots: 5, trueWindAngleDegrees: 95) == nil)
        #expect(profile.sailCombination(trueWindSpeedKnots: 3, trueWindAngleDegrees: 90) == nil)
        #expect(profile.sailCombination(trueWindSpeedKnots: 12, trueWindAngleDegrees: 20) == nil)

        let beam = profile.resolve(trueHeading: 90, trueWindDirection: 0, trueWindSpeedKnots: 12)
        #expect(beam.pointOfSail == .beamReach)
        #expect(beam.sailCombination == .up)
        let gap = profile.resolve(trueHeading: 95, trueWindDirection: 0, trueWindSpeedKnots: 12)
        #expect(gap.pointOfSail == .beamReach)
        #expect(gap.sailCombination == nil)
    }

    @Test
    func provenanceNamesTheFarrSetAndLeavesNimanaEmpty() {
        let extasy = SailingProfile.extasy.datasets
        #expect(extasy.count == 1)
        #expect(extasy.first?.provenance.kind == .manufacturer)
        #expect(extasy.first?.provenance.boatIdentifier == "extasy")
        #expect(extasy.first?.provenance.reference.contains("Design #354") == true)
        #expect(extasy.first?.provenance.version?.contains("2.87") == true)
        #expect(SailingProfile.nimana.datasets.isEmpty)
        #expect(SailingProfile.nimana.optimalUpwindTrueWindAngle(trueWindSpeedKnots: 12) == nil)
        #expect(SailingProfile.nimana.sailCombination(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) == nil)
        #expect(BoatProfile.nimana.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) == nil)
        #expect(BoatProfile.nimana.hasSpeedPolar == false)
        let kinds = BoatProfile.allCases.flatMap { $0.sailingProfile.datasets.map(\.provenance.kind) }
        #expect(kinds == [.manufacturer])
    }

    @Test
    func ambiguousAxesRejectWithoutATack() {
        let profile = SailingProfile.extasy
        #expect(profile.resolve(trueHeading: 0, trueWindDirection: 0, trueWindSpeedKnots: 12).tack == nil)
        #expect(profile.rejectionReason(for: .tack(.port), trueHeading: 0, trueWindDirection: 0, trueWindSpeedKnots: 12)?.contains("No-go") == true)
        #expect(profile.resolve(trueHeading: 180, trueWindDirection: 0, trueWindSpeedKnots: 12).tack == nil)
        let downwind = profile.rejectionReason(for: .gybe(.port), trueHeading: 180, trueWindDirection: 0, trueWindSpeedKnots: 12)
        #expect(downwind?.contains("Dead downwind") == true)
    }

    @Test @MainActor
    func rejectedCommandLeavesHeadingAndGivesAReason() {
        let simulator = makeSailingSimulator(heading: 45, wind: 0)
        simulator.beginManeuver(.gybe(.starboard))
        #expect(simulator.activeManeuver == nil)
        #expect(simulator.gyroHeading.value == 45)
        #expect(simulator.maneuverRejectionReason?.contains("Close-hauled") == true)

        simulator.beginManeuver(.tack(.starboard))
        #expect(simulator.activeManeuver?.kind == .tack)
        #expect(simulator.maneuverRejectionReason == nil)
        #expect(simulator.gyroHeading.value == 45)
    }

    @Test @MainActor
    func broadReachRejectsATackAndKeepsTheHeading() {
        let simulator = makeSailingSimulator(heading: 120, wind: 0)
        simulator.beginManeuver(.tack(.starboard))
        #expect(simulator.activeManeuver == nil)
        #expect(simulator.gyroHeading.value == 120)
        #expect(simulator.maneuverRejectionReason?.contains("Broad reach") == true)
    }

    @Test
    func aRunningManeuverIsNotCancelledWhenTheWindAngleEntersNoGo() {
        var rig = SailingRig()
        let start = rig.time
        rig.state.activeManeuver = ActiveManeuver(
            kind: .tack,
            side: .starboard,
            startedAt: start,
            duration: 10,
            fromTrueHeading: 45,
            toTrueHeading: 315,
            trueWindDirection: 0,
            turnDelta: -90,
            drivesHeading: true
        )
        rig.state.twd.value = 50
        rig.state.twd.centerValue = 50
        let snapshot = tick(&rig, at: start.addingTimeInterval(1))
        #expect(rig.state.vesselObservation.sailingState?.pointOfSail == .noGo)
        #expect(rig.state.activeManeuver?.kind == .tack)
        let truth = rig.state.vesselTruth.trueHeading
        #expect(abs(calculateShortestRotation(from: truth, to: snapshot.gyroHeading ?? -1)) < 0.001)
        #expect(NMEANumericFormatting.format(truth, fractionDigits: 1) == NMEANumericFormatting.format(snapshot.gyroHeading ?? -1, fractionDigits: 1))
    }
}

private struct SailingRig {
    var state: SimulationState
    var config: SimulationConfig
    var time = Date(timeIntervalSince1970: 1_800_005_000)

    init() {
        let simulator = makeSailingSimulator(heading: 45, wind: 0)
        state = SimulationState(from: simulator)
        state.lastSensorEvolutionDate = time
        config = simulator.captureSimulationConfig()
    }
}

private func tick(_ rig: inout SailingRig, at time: Date) -> SimulationSnapshot {
    SimulationEngine.tickSimulation(
        state: &rig.state,
        config: rig.config,
        at: time,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
}

private func makeSailingSimulator(heading: Double, wind: Double) -> NMEASimulator {
    let suite = "SailingState.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.boatSpeedMode = .manual
    simulator.boatProfile = .beneteauFirst407
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: heading, offset: 0, value: heading)
    simulator.twd = SimulatedValue(type: .windDirection, center: wind, offset: 0, value: wind)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    return simulator
}
