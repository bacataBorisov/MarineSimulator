import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselSailTests {

    @Test
    func certificateSailsStaySeparateAndOptional() {
        let extasy = BuiltInVesselID.seeds[0]
        #expect(extasy.inventory.map(\.id) == [
            ReferenceSailID.extasyMainsail,
            ReferenceSailID.extasyJib2,
            ReferenceSailID.extasyHeadsail1,
            ReferenceSailID.extasyAsymmetric
        ])
        #expect(extasy.inventory.filter { $0.category == .headsail }.count == 2)
        #expect(extasy.inventory.first { $0.id == ReferenceSailID.extasyMainsail }?.mainsail?.luffMeters == nil)
        #expect(extasy.inventory.first { $0.id == ReferenceSailID.extasyMainsail }?.mainsail?.areaSquareMeters == 44.92)
        #expect(extasy.inventory.allSatisfy { $0.provenance?.status == .certificateListed })
        #expect(extasy.activeSails.mainsailID == nil)

        let nimana = BuiltInVesselID.seeds[1]
        let asymmetric = nimana.inventory.filter { $0.category == .asymmetricSpinnaker }
        #expect(asymmetric.map(\.identification) == ["0", "11", "A0"])
        #expect(Set(asymmetric.map(\.id)).count == 3)
        let a0 = asymmetric.first { $0.identification == "A0" }
        #expect(a0?.downwind?.halfWidthMeters == 7.56)
        #expect(a0?.downwind?.footMeters == 10.07)
        #expect(nimana.inventory.first { $0.id == ReferenceSailID.nimanaHeadsail }?.headsail?.luffPerpendicularMeters == 5.97)
        #expect(nimana.inventory.first { $0.id == ReferenceSailID.nimanaHeadsail }?.headsail?.luffMeters == 17.50)
    }

    @Test
    func sailsPersistDuplicateAndStayOnTheirVessel() throws {
        let simulator = sailSimulator()
        let custom = try simulator.createCustomVessel(name: "Skiff", modelName: "One", constructionYear: 2024)
        let mainID = UUID()
        let kiteID = UUID()
        let inventory = [
            SailRecord(id: mainID, name: "Main A", category: .mainsail, mainsail: MainsailMeasurements(areaSquareMeters: 20)),
            SailRecord(id: kiteID, name: "Kite A", category: .asymmetricSpinnaker, downwind: DownwindMeasurements(luffMeters: 12)),
            SailRecord(id: UUID(), name: "Kite B", category: .asymmetricSpinnaker)
        ]
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: inventory)
        let stored = try #require(simulator.vessels.first { $0.id == custom.id })
        #expect(stored.id == custom.id)
        #expect(stored.inventory.map(\.id) == inventory.map(\.id))
        #expect(stored.inventory.first { $0.id == mainID }?.mainsail?.luffMeters == nil)
        #expect(stored.inventory.filter { $0.category == .asymmetricSpinnaker }.count == 2)

        let copy = try simulator.duplicateVessel(custom.id)
        #expect(copy.inventory.count == 3)
        #expect(Set(copy.inventory.map(\.id)).isDisjoint(with: Set(inventory.map(\.id))))
        #expect(copy.performance == VesselProfile.Performance.none)

        let extasySail = ReferenceSailID.extasyMainsail
        #expect(throws: VesselProfileStoreError.self) {
            try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: extasySail))
        }
        #expect(simulator.vessels.first { $0.id == custom.id }?.activeSails.mainsailID == nil)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.inventory.contains { $0.id == extasySail } == true)
    }

    @Test
    func activeSlotsRejectIncompatibleAndMissingSails() throws {
        let simulator = sailSimulator()
        let custom = try simulator.createCustomVessel(name: "Skiff")
        let main = SailRecord(id: UUID(), name: "Main", category: .mainsail, mainsail: MainsailMeasurements(reefCount: 1))
        let jib = SailRecord(id: UUID(), name: "Jib", category: .headsail)
        let kite = SailRecord(id: UUID(), name: "Kite", category: .asymmetricSpinnaker)
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [main, jib, kite])

        #expect(throws: VesselProfileStoreError.self) {
            try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: jib.id))
        }
        #expect(throws: VesselProfileStoreError.self) {
            try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: UUID()))
        }
        #expect(throws: VesselProfileStoreError.self) {
            try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: main.id, headsailID: main.id))
        }
        #expect(throws: VesselProfileStoreError.self) {
            try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: main.id, mainsailReef: .reef3))
        }
        try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: main.id, headsailID: jib.id, downwindSailID: kite.id, mainsailReef: .reef1))
        let selected = try #require(simulator.vessels.first { $0.id == custom.id }?.activeSails)
        #expect(selected.mainsailID == main.id)
        #expect(selected.runtimeConfiguration.mainSailID == main.id.uuidString)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(simulator.sailConfiguration.mainSailID == nil)
    }

    @Test
    func deletingTheActiveSailClearsOnlyThatSlot() throws {
        let simulator = sailSimulator()
        let custom = try simulator.createCustomVessel(name: "Skiff")
        simulator.selectVessel(custom.id)
        let main = SailRecord(id: UUID(), name: "Main", category: .mainsail)
        let jib = SailRecord(id: UUID(), name: "Jib", category: .headsail)
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [main, jib])
        try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: main.id, headsailID: jib.id))
        try simulator.setHoistedSails(ActiveSailSelection(mainsailID: main.id, headsailID: jib.id))
        #expect(simulator.sailConfiguration.mainSailID == main.id.uuidString)
        let heading = simulator.gyroHeading.value
        let speed = simulator.speed.value

        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [jib])
        #expect(simulator.vessels.first { $0.id == custom.id }?.activeSails.mainsailID == nil)
        #expect(simulator.vessels.first { $0.id == custom.id }?.activeSails.headsailID == jib.id)
        #expect(simulator.sailConfiguration.mainSailID == nil)
        #expect(simulator.sailConfiguration.headsailID == jib.id.uuidString)
        #expect(simulator.gyroHeading.value == heading)
        #expect(simulator.speed.value == speed)
        #expect(simulator.activeManeuver == nil)
    }

    @Test
    func switchingVesselsUsesThatVesselsSails() throws {
        let simulator = sailSimulator()
        let main = ReferenceSailID.extasyMainsail
        let heading = simulator.gyroHeading.centerValue
        let speed = simulator.speed.value
        try simulator.replaceActiveSails(BuiltInVesselID.extasy, with: ActiveSailSelection(mainsailID: main))
        #expect(simulator.sailConfiguration.mainSailID == nil)
        simulator.selectVessel(BuiltInVesselID.nimana)
        #expect(simulator.sailConfiguration.mainSailID == nil)
        #expect(simulator.selectedVesselID == BuiltInVesselID.nimana)
        #expect(simulator.gyroHeading.centerValue == heading)
        #expect(simulator.speed.value == speed)
        #expect(simulator.boatProfile == .nimana)
        simulator.selectVessel(BuiltInVesselID.extasy)
        #expect(simulator.sailConfiguration.mainSailID == main.uuidString)
        #expect(simulator.boatProfile == .beneteauFirst407)
    }

    @Test
    func builtInSailsCanChangeWithoutChangingIdentity() throws {
        let simulator = sailSimulator()
        let added = SailRecord(id: UUID(), name: "Delivery main", category: .mainsail, mainsail: MainsailMeasurements(luffMeters: 14))
        var inventory = try #require(simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.inventory)
        inventory.append(added)
        try simulator.saveProfileEdits(BuiltInVesselID.extasy, metadata: nil, inventory: inventory)
        let stored = try #require(simulator.vessels.first { $0.id == BuiltInVesselID.extasy })
        #expect(stored.name == "Extasy")
        #expect(stored.id == BuiltInVesselID.extasy)
        #expect(stored.performance == .farrDesign354)
        #expect(stored.hull.lengthOverallMeters == 11.924)
        #expect(stored.inventory.contains { $0.id == added.id })
        #expect(throws: VesselProfileStoreError.builtInProfileIsProtected(BuiltInVesselID.extasy)) {
            try simulator.updateCustomVessel(BuiltInVesselID.extasy, metadata: VesselEditableMetadata(
                name: "Renamed",
                manufacturer: "Beneteau",
                modelName: "Beneteau First 40.7",
                constructionYear: 1999,
                sailNumber: "ITA-13903",
                registration: nil,
                hull: stored.hull,
                rig: stored.rig
            ))
        }
    }

    @Test
    func missingInventoryStaysEmptyAndABadInventoryIsLeftOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sails.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(FileVesselProfileStore.fileName)
        let legacy = """
        {"schemaVersion":2,"profiles":[
        {"id":"\(BuiltInVesselID.extasy.uuidString)","name":"Extasy","modelName":"Beneteau First 40.7","constructionYear":1999,"origin":"builtIn","performance":"farrDesign354","manufacturer":"Beneteau","sailNumber":"ITA-13903"},
        {"id":"\(BuiltInVesselID.nimana.uuidString)","name":"Nimana","modelName":"Bavaria Cruiser 46","constructionYear":2015,"origin":"builtIn","performance":"none"}
        ]}
        """
        try Data(legacy.utf8).write(to: url, options: .atomic)
        let migrated = VesselProfileRepository(store: FileVesselProfileStore(directory: directory))
        #expect(migrated.loadError == nil)
        #expect(migrated.profile(id: BuiltInVesselID.extasy)?.inventory.isEmpty == true)
        #expect(migrated.profile(id: BuiltInVesselID.extasy)?.sailNumber == "ITA-13903")
        #expect(migrated.profile(id: BuiltInVesselID.extasy)?.hull.lengthOverallMeters == 11.924)
        #expect(migrated.document?.schemaVersion == 3)

        let badSail = """
        {"id":"\(UUID().uuidString)","name":"Bad","category":"mainsail","mainsail":{"areaSquareMeters":-1}}
        """
        let broken = """
        {"schemaVersion":3,"profiles":[
        {"id":"\(BuiltInVesselID.extasy.uuidString)","name":"Extasy","origin":"builtIn","performance":"farrDesign354","inventory":[\(badSail)]},
        {"id":"\(BuiltInVesselID.nimana.uuidString)","name":"Nimana","origin":"builtIn","performance":"none","inventory":[]}
        ]}
        """
        let bytes = Data(broken.utf8)
        try bytes.write(to: url, options: .atomic)
        let rejected = VesselProfileRepository(store: FileVesselProfileStore(directory: directory))
        if case .invalidProfileData = rejected.loadError {} else {
            Issue.record("Expected invalid sail data")
        }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test
    func sailEditsAutosaveAndInvalidMeasurementsStayUnstored() throws {
        let simulator = sailSimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: simulator))
        session.show(custom.id, on: simulator)
        let sailID = UUID()
        session.buffer.sails = [SailDraft(id: sailID, name: "Main", category: .mainsail)]
        session.persistValidEdits(on: simulator)
        #expect(session.hasUnsavedChanges(in: simulator) == false)
        let created = try #require(simulator.vessels.first { $0.id == custom.id }?.inventory.first)
        #expect(created.id == sailID)
        #expect(created.name == "Main")
        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .allowed)
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        session.show(custom.id, on: simulator)
        session.buffer.sails[0].area = "20."
        session.persistValidEdits(on: simulator)
        #expect(session.buffer.sails[0].area == "20.")
        #expect(session.validationMessage?.contains("number") == true)
        #expect(simulator.vessels.first { $0.id == custom.id }?.inventory.first?.mainsail?.areaSquareMeters == nil)
        session.buffer.sails[0].area = "20"
        session.persistValidEdits(on: simulator)
        let stored = try #require(simulator.vessels.first { $0.id == custom.id }?.inventory.first)
        #expect(stored.id == sailID)
        #expect(stored.mainsail?.areaSquareMeters == 20)
        #expect(stored.mainsail?.luffMeters == nil)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func failedSailSaveKeepsTheDraft() throws {
        let store = RejectingSailStore()
        let simulator = sailSimulator(store: store)
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: nil, constructionYear: nil, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.sails = [SailDraft(id: UUID(), name: "Main", category: .mainsail)]
        session.buffer.sails[0].luff = "nope"
        #expect(session.saveBuffer(on: simulator) == false)
        #expect(session.buffer.sails[0].luff == "nope")
        #expect(session.failureMessage?.contains("number") == true)

        session.buffer.sails[0].luff = ""
        store.rejectWrites = true
        #expect(session.saveBuffer(on: simulator) == false)
        #expect(session.buffer.sails[0].name == "Main")
        #expect(simulator.vessels.first { $0.id == custom.id }?.inventory.isEmpty == true)
    }

    @Test
    func sailsDoNotChangeSpeedOrLeakIntoTheObservation() throws {
        let extasy = sailTick(profileID: BuiltInVesselID.extasy, speed: 4)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs((extasy.speed ?? 0) - polar) < 0.000_001)

        let simulator = sailSimulator()
        let custom = try simulator.createCustomVessel(name: "Skiff")
        let sail = SailRecord(id: UUID(), name: "Main", category: .mainsail, mainsail: MainsailMeasurements(areaSquareMeters: 44.92))
        try simulator.saveProfileEdits(custom.id, metadata: nil, inventory: [sail])
        try simulator.replaceActiveSails(custom.id, with: ActiveSailSelection(mainsailID: sail.id))
        simulator.selectVessel(custom.id)
        let held = sailTick(simulator: simulator, profileID: custom.id, speed: 5.25)
        #expect(abs((held.speed ?? 0) - 5.25) < 0.000_001)
        #expect(simulator.boatProfile.hasSpeedPolar == false)
        #expect(held.observation.sailConfiguration.mainSailID == sail.id.uuidString)
        let visible = String(reflecting: held.observation)
        #expect(visible.contains(sail.id.uuidString))
        #expect(visible.contains("44.92") == false)
        #expect(visible.contains("hidden") == false)
    }
}

private struct SailTickSample {
    var speed: Double?
    var observation: VesselObservation
}

private func sailTick(profileID: UUID, speed: Double) -> SailTickSample {
    sailTick(simulator: sailSimulator(), profileID: profileID, speed: speed)
}

private func sailTick(simulator: NMEASimulator, profileID: UUID, speed: Double) -> SailTickSample {
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.selectVessel(profileID)
    simulator.boatSpeedMode = .estimated
    simulator.speed = SimulatedValue(type: .speedLog, center: speed, offset: 0, value: speed)
    let time = Date(timeIntervalSince1970: 1_800_006_500)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: time)
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    var state = SimulationState(from: simulator)
    state.lastSensorEvolutionDate = time
    state.lastSimulationTickDate = time.addingTimeInterval(-0.05)
    _ = SimulationEngine.tickSimulation(
        state: &state,
        config: simulator.captureSimulationConfig(),
        at: time,
        liveWeatherValueGenerator: { base, _, _, _ in base }
    )
    return SailTickSample(speed: state.vesselTruth.speedThroughWaterKnots, observation: state.vesselObservation)
}

private final class RejectingSailStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    var rejectWrites = false

    func loadDocument() throws -> VesselProfileDocument? { document }

    func saveDocument(_ document: VesselProfileDocument) throws {
        if rejectWrites {
            throw VesselProfileStoreError.writeFailure("disk full")
        }
        self.document = document
    }
}

private func sailSimulator(store: (any VesselProfileStoring)? = nil) -> NMEASimulator {
    let suite = "VesselSail.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return NMEASimulator(userDefaults: defaults, vesselStore: store ?? InMemoryVesselProfileStore())
}
