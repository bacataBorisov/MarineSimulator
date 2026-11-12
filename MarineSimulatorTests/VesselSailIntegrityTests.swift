import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselSailIntegrityTests {

    @Test
    func theFirstCycleAfterAVesselSwitchPublishesThatVesselsSails() throws {
        let simulator = integritySimulator()
        try simulator.replaceActiveSails(BuiltInVesselID.extasy, with: ActiveSailSelection(mainsailID: ReferenceSailID.extasyMainsail, mainsailReef: .reef2))
        try simulator.replaceActiveSails(BuiltInVesselID.nimana, with: ActiveSailSelection(headsailID: ReferenceSailID.nimanaHeadsail))
        simulator.selectVessel(BuiltInVesselID.extasy)
        prepare(simulator)
        cycle(simulator)
        let heading = simulator.gyroHeading.value
        let speed = simulator.speed.value
        #expect(simulator.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(simulator.vesselObservation.sailConfiguration.mainSailID == ReferenceSailID.extasyMainsail.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.mainsailReef == .reef2)

        simulator.selectVessel(BuiltInVesselID.nimana)
        #expect(simulator.vesselObservation.sailConfiguration.mainSailID == nil)
        #expect(simulator.vesselObservation.sailConfiguration.headsailID == ReferenceSailID.nimanaHeadsail.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.mainsailReef == .full)
        #expect(simulator.vesselObservation.referenceProfile == .nimana)
        #expect(simulator.gyroHeading.value == heading)
        #expect(simulator.speed.value == speed)
        cycle(simulator)
        #expect(simulator.vesselObservation.sailConfiguration.headsailID == ReferenceSailID.nimanaHeadsail.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.hoistedIDs.contains(ReferenceSailID.extasyMainsail.uuidString) == false)

        simulator.selectVessel(BuiltInVesselID.extasy)
        cycle(simulator)
        #expect(simulator.vesselObservation.referenceProfile == .beneteauFirst407)
        #expect(simulator.vesselObservation.sailConfiguration.mainSailID == ReferenceSailID.extasyMainsail.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.mainsailReef == .reef2)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        let extasySpeed = sailSpeed(simulator)
        #expect(abs((extasySpeed ?? 0) - polar) < 0.000_001)
    }

    @Test
    func aRunningTransmitCycleUsesTheNewVesselBeforeTheNextPublication() throws {
        let simulator = integritySimulator()
        try simulator.replaceActiveSails(
            BuiltInVesselID.extasy,
            with: ActiveSailSelection(headsailID: ReferenceSailID.extasyJib2)
        )
        simulator.selectVessel(BuiltInVesselID.extasy)
        prepare(simulator)
        simulator.transmitRuntime = SimulationState(from: simulator)
        let maneuver = ActiveManeuver(
            kind: .tack,
            startedAt: Date(timeIntervalSince1970: 1_800_007_000),
            duration: 8,
            fromTrueHeading: 90,
            toTrueHeading: 270,
            trueWindDirection: 180,
            drivesHeading: true
        )
        simulator.activeManeuver = maneuver
        simulator.transmitRuntime?.activeManeuver = maneuver
        let heading = simulator.gyroHeading.value

        simulator.selectVessel(BuiltInVesselID.nimana)
        #expect(simulator.transmitRuntime?.vesselObservation.referenceProfile == .nimana)
        #expect(simulator.transmitRuntime?.vesselObservation.sailConfiguration.hoistedIDs.isEmpty == true)
        #expect(simulator.activeManeuver?.kind == .tack)
        #expect(simulator.activeManeuver?.fromTrueHeading == 90)
        #expect(simulator.gyroHeading.value == heading)

        simulator.runTransmitSimulationCycle(at: maneuver.startedAt.addingTimeInterval(0.05))
        let published = try #require(simulator.transmitRuntime?.vesselObservation)
        #expect(published.referenceProfile == .nimana)
        #expect(published.sailConfiguration.hoistedIDs.isEmpty)
        #expect(simulator.transmitRuntime?.activeManeuver?.kind == .tack)
    }

    @Test
    func customVesselsDoNotInheritAnotherInventory() throws {
        let simulator = integritySimulator()
        let first = try simulator.createCustomVessel(name: "Alpha")
        let second = try simulator.createCustomVessel(name: "Beta")
        let alphaMain = SailRecord(id: UUID(), name: "Alpha main", category: .mainsail)
        let betaJib = SailRecord(id: UUID(), name: "Beta jib", category: .headsail)
        try simulator.saveProfileEdits(first.id, metadata: nil, inventory: [alphaMain])
        try simulator.saveProfileEdits(second.id, metadata: nil, inventory: [betaJib])
        try simulator.replaceActiveSails(first.id, with: ActiveSailSelection(mainsailID: alphaMain.id))
        try simulator.replaceActiveSails(second.id, with: ActiveSailSelection(headsailID: betaJib.id))

        simulator.selectVessel(first.id)
        prepare(simulator)
        cycle(simulator)
        #expect(simulator.vesselObservation.sailConfiguration.mainSailID == alphaMain.id.uuidString)
        #expect(simulator.boatProfile.hasSpeedPolar == false)

        let empty = try simulator.createCustomVessel(name: "Empty")
        simulator.selectVessel(empty.id)
        #expect(simulator.sailConfiguration.hoistedIDs.isEmpty)
        cycle(simulator)
        #expect(simulator.vesselObservation.sailConfiguration.hoistedIDs.isEmpty)
        #expect(simulator.vesselObservation.sailConfiguration.hoistedIDs.contains(alphaMain.id.uuidString) == false)

        simulator.selectVessel(second.id)
        cycle(simulator)
        #expect(simulator.vesselObservation.sailConfiguration.headsailID == betaJib.id.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.mainSailID == nil)
        let visible = String(reflecting: simulator.vesselObservation)
        #expect(visible.contains(alphaMain.id.uuidString) == false)
        #expect(visible.contains("hidden") == false)
        #expect(visible.contains("44.92") == false)
    }

    @Test
    func aRuntimeHoistDoesNotRewriteTheSavedSelection() throws {
        let simulator = integritySimulator()
        let saved = ActiveSailSelection(headsailID: ReferenceSailID.extasyHeadsail1)
        try simulator.replaceActiveSails(BuiltInVesselID.extasy, with: saved)
        simulator.selectVessel(BuiltInVesselID.nimana)
        simulator.selectVessel(BuiltInVesselID.extasy)
        #expect(simulator.sailConfiguration.headsailID == ReferenceSailID.extasyHeadsail1.uuidString)
        let storedBefore = simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.activeSails

        try simulator.setHoistedSails(ActiveSailSelection(headsailID: ReferenceSailID.extasyJib2))
        prepare(simulator)
        cycle(simulator)
        #expect(simulator.vesselObservation.sailConfiguration.headsailID == ReferenceSailID.extasyJib2.uuidString)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.activeSails == storedBefore)

        simulator.selectVessel(BuiltInVesselID.nimana)
        simulator.selectVessel(BuiltInVesselID.extasy)
        cycle(simulator)
        #expect(simulator.vesselObservation.sailConfiguration.headsailID == ReferenceSailID.extasyHeadsail1.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.headsailID != ReferenceSailID.extasyJib2.uuidString)
    }

    @Test
    func deletingAHoistedSailClearsThatSlotAndAFailedWriteLeavesBothStates() throws {
        let store = RejectingIntegrityStore()
        let simulator = integritySimulator(store: store)
        let custom = try simulator.createCustomVessel(name: "Skiff")
        simulator.selectVessel(custom.id)
        let main = SailRecord(id: UUID(), name: "Main", category: .mainsail, mainsail: MainsailMeasurements(areaSquareMeters: 10))
        let jib = SailRecord(id: UUID(), name: "Jib", category: .headsail)
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [main, jib])
        try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: main.id))
        try simulator.setHoistedSails(ActiveSailSelection(mainsailID: main.id, headsailID: jib.id))
        let heading = simulator.gyroHeading.value

        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [jib])
        #expect(simulator.vessels.first { $0.id == custom.id }?.activeSails.mainsailID == nil)
        #expect(simulator.sailConfiguration.mainSailID == nil)
        #expect(simulator.sailConfiguration.headsailID == jib.id.uuidString)
        #expect(simulator.vesselObservation.sailConfiguration.mainSailID == nil)
        #expect(simulator.gyroHeading.value == heading)

        let renamed = SailRecord(id: jib.id, name: "Jib II", category: .headsail)
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [renamed])
        #expect(simulator.vessels.first { $0.id == custom.id }?.inventory.first?.id == jib.id)
        #expect(simulator.sailConfiguration.headsailID == jib.id.uuidString)

        let copy = try simulator.duplicateVessel(custom.id)
        #expect(copy.inventory.first?.id != jib.id)
        #expect(simulator.sailConfiguration.headsailID == jib.id.uuidString)

        store.rejectWrites = true
        let hoisted = simulator.sailConfiguration
        #expect(throws: VesselProfileStoreError.self) {
            try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [])
        }
        #expect(simulator.sailConfiguration == hoisted)
        #expect(simulator.vessels.first { $0.id == custom.id }?.inventory.map(\.id) == [jib.id])
    }

    @Test
    func anUnresolvedVesselClearsSailsAndARestartRestoresTheSavedSelection() throws {
        let store = InMemoryIntegrityStore()
        let suite = "SailIntegrity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults, vesselStore: store)
        let custom = try simulator.createCustomVessel(name: "Skiff")
        let sail = SailRecord(id: UUID(), name: "Main", category: .mainsail)
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [sail])
        try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: sail.id))
        simulator.selectVessel(custom.id)
        try simulator.setHoistedSails(ActiveSailSelection())
        #expect(simulator.sailConfiguration.hoistedIDs.isEmpty)

        try simulator.deleteCustomVessel(custom.id)
        #expect(simulator.vesselAllowsSimulation == false)
        #expect(simulator.sailConfiguration.hoistedIDs.isEmpty)
        #expect(simulator.vesselObservation.sailConfiguration.hoistedIDs.isEmpty)
        simulator.runSimulationCycle(at: Date(timeIntervalSince1970: 1_800_007_200))
        #expect(simulator.vesselObservation.sailConfiguration.hoistedIDs.isEmpty)
    }

    @Test
    func restartAdoptsTheSavedSelection() throws {
        let store = InMemoryIntegrityStore()
        let suite = "SailIntegrityRestart.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults, vesselStore: store)
        try simulator.replaceActiveSails(
            BuiltInVesselID.extasy,
            with: ActiveSailSelection(mainsailID: ReferenceSailID.extasyMainsail, mainsailReef: .reef1)
        )
        simulator.selectVessel(BuiltInVesselID.extasy)
        simulator.persistLiveSettings()

        let restarted = NMEASimulator(userDefaults: defaults, vesselStore: store)
        #expect(restarted.selectedVesselID == BuiltInVesselID.extasy)
        #expect(restarted.sailConfiguration.mainSailID == ReferenceSailID.extasyMainsail.uuidString)
        #expect(restarted.sailConfiguration.mainsailReef == .reef1)
        #expect(restarted.vesselObservation.sailConfiguration.mainSailID == ReferenceSailID.extasyMainsail.uuidString)
    }
}

private final class InMemoryIntegrityStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    func loadDocument() throws -> VesselProfileDocument? { document }
    func saveDocument(_ document: VesselProfileDocument) throws { self.document = document }
}

private final class RejectingIntegrityStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    var rejectWrites = false
    func loadDocument() throws -> VesselProfileDocument? { document }
    func saveDocument(_ document: VesselProfileDocument) throws {
        if rejectWrites { throw VesselProfileStoreError.writeFailure("disk full") }
        self.document = document
    }
}

private func integritySimulator(store: (any VesselProfileStoring)? = nil) -> NMEASimulator {
    let suite = "SailIntegrityRun.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return NMEASimulator(userDefaults: defaults, vesselStore: store ?? InMemoryIntegrityStore())
}

private func prepare(_ simulator: NMEASimulator) {
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.boatSpeedMode = .estimated
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasSpeedLog = true
    let time = Date(timeIntervalSince1970: 1_800_007_000)
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.speed = SimulatedValue(type: .speedLog, center: 4, offset: 0, value: 4)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
}

private func cycle(_ simulator: NMEASimulator) {
    simulator.runSimulationCycle(at: Date(timeIntervalSince1970: 1_800_007_050))
}

private func sailSpeed(_ simulator: NMEASimulator) -> Double? {
    var state = SimulationState(from: simulator)
    let time = Date(timeIntervalSince1970: 1_800_007_080)
    state.lastSensorEvolutionDate = time
    state.lastSimulationTickDate = time.addingTimeInterval(-0.05)
    _ = SimulationEngine.tickSimulation(
        state: &state,
        config: simulator.captureSimulationConfig(),
        at: time,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
    return state.vesselTruth.speedThroughWaterKnots
}
