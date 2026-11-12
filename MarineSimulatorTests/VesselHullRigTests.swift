import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselHullRigTests {

    @Test
    func seededMeasurementsMatchTheRenderedCertificates() {
        let extasy = BuiltInVesselID.seeds[0]
        #expect(extasy.id == BuiltInVesselID.extasy)
        #expect(extasy.manufacturer == "Beneteau")
        #expect(extasy.modelName == "Beneteau First 40.7")
        #expect(extasy.constructionYear == 1999)
        #expect(extasy.sailNumber == "ITA-13903")
        #expect(extasy.registration == nil)
        #expect(extasy.hull.lengthOverallMeters == 11.924)
        #expect(extasy.hull.waterlineLengthMeters == nil)
        #expect(extasy.hull.beamMeters == 3.770)
        #expect(extasy.hull.draftMeters == 2.425)
        #expect(extasy.hull.displacementKilograms == 7_272)
        #expect(extasy.rig.foretriangleHeightMeters == nil)
        #expect(extasy.rig.foretriangleBaseMeters == 4.420)
        #expect(extasy.rig.mainsailLuffMeters == 14.710)
        #expect(extasy.rig.mainsailFootMeters == 5.370)
        #expect(extasy.performance == .farrDesign354)

        let nimana = BuiltInVesselID.seeds[1]
        #expect(nimana.manufacturer == "Bavaria")
        #expect(nimana.modelName == "Bavaria Cruiser 46")
        #expect(nimana.constructionYear == 2015)
        #expect(nimana.sailNumber == "BUL 46")
        #expect(nimana.registration == nil)
        #expect(nimana.hull.lengthOverallMeters == 13.600)
        #expect(nimana.hull.waterlineLengthMeters == nil)
        #expect(nimana.hull.beamMeters == 4.352)
        #expect(nimana.hull.draftMeters == 2.108)
        #expect(nimana.hull.displacementKilograms == 12_888)
        #expect(nimana.rig.foretriangleHeightMeters == nil)
        #expect(nimana.rig.foretriangleBaseMeters == 5.510)
        #expect(nimana.rig.mainsailLuffMeters == 16.550)
        #expect(nimana.rig.mainsailFootMeters == 5.450)
        #expect(nimana.performance == .none)
    }

    @Test
    func customMetadataPersistsAndKeepsTheUUID() throws {
        let simulator = hullSimulator()
        let created = try simulator.createCustomVessel(name: "Skiff", modelName: "One", constructionYear: 2020)
        let metadata = VesselEditableMetadata(
            name: "Skiff",
            manufacturer: "Yard",
            modelName: "One",
            constructionYear: 2020,
            sailNumber: "BUL 1",
            registration: "BG 100",
            hull: HullDimensions(lengthOverallMeters: 8.2, displacementKilograms: 2_400),
            rig: RigDimensions(foretriangleBaseMeters: 3.1, mainsailFootMeters: 3.4)
        )
        try simulator.updateCustomVessel(created.id, metadata: metadata)
        let stored = try #require(simulator.vessels.first { $0.id == created.id })
        #expect(stored.id == created.id)
        #expect(stored.origin == .custom)
        #expect(stored.performance == .none)
        #expect(stored.manufacturer == "Yard")
        #expect(stored.sailNumber == "BUL 1")
        #expect(stored.registration == "BG 100")
        #expect(stored.hull.lengthOverallMeters == 8.2)
        #expect(stored.hull.waterlineLengthMeters == nil)
        #expect(stored.hull.beamMeters == nil)
        #expect(stored.hull.draftMeters == nil)
        #expect(stored.hull.displacementKilograms == 2_400)
        #expect(stored.rig.foretriangleHeightMeters == nil)
        #expect(stored.rig.foretriangleBaseMeters == 3.1)
        #expect(stored.rig.mainsailLuffMeters == nil)
        #expect(stored.rig.mainsailFootMeters == 3.4)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        let data = try JSONEncoder().encode(VesselProfileDocument(schemaVersion: 2, profiles: simulator.vessels))
        let decoded = try JSONDecoder().decode(VesselProfileDocument.self, from: data)
        let roundTrip = try #require(decoded.profiles.first { $0.id == created.id })
        #expect(roundTrip.hull.waterlineLengthMeters == nil)
        #expect(roundTrip.rig.mainsailLuffMeters == nil)
        #expect(roundTrip.hull.lengthOverallMeters == 8.2)
    }

    @Test
    func invalidMeasurementsAreRejectedAndLeaveTheLibrary() throws {
        let simulator = hullSimulator()
        let created = try simulator.createCustomVessel(name: "Skiff", modelName: "One", constructionYear: 2020)
        let cases: [VesselEditableMetadata] = [
            metadata(name: "Skiff", year: 1799, loa: nil),
            metadata(name: "Skiff", year: 2020, loa: 0),
            metadata(name: "Skiff", year: 2020, loa: -1),
            metadata(name: " ", year: 2020, loa: 8)
        ]
        for candidate in cases {
            #expect(throws: VesselProfileStoreError.self) {
                try simulator.updateCustomVessel(created.id, metadata: candidate)
            }
        }
        let stored = try #require(simulator.vessels.first { $0.id == created.id })
        #expect(stored.name == "Skiff")
        #expect(stored.constructionYear == 2020)
        #expect(stored.hull.lengthOverallMeters == nil)
    }

    @Test
    func schemaOneLibrariesMigrateAndInvalidLibrariesStayOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HullRig.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(FileVesselProfileStore.fileName)
        let customID = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
        let schemaOne = """
        {"schemaVersion":1,"profiles":[
        {"id":"\(BuiltInVesselID.extasy.uuidString)","name":"Extasy","modelName":"Beneteau First 40.7","constructionYear":1999,"origin":"builtIn","performance":"farrDesign354"},
        {"id":"\(BuiltInVesselID.nimana.uuidString)","name":"Nimana","modelName":"Bavaria Cruiser 46","constructionYear":2015,"origin":"builtIn","performance":"none"},
        {"id":"\(customID.uuidString)","name":"Skiff","modelName":"One","constructionYear":2020,"origin":"custom","performance":"none"}
        ]}
        """
        try Data(schemaOne.utf8).write(to: url, options: .atomic)
        let migrated = VesselProfileRepository(store: FileVesselProfileStore(directory: directory))
        #expect(migrated.loadError == nil)
        #expect(migrated.document?.schemaVersion == 3)
        let custom = try #require(migrated.profile(id: customID))
        #expect(custom.name == "Skiff")
        #expect(custom.modelName == "One")
        #expect(custom.constructionYear == 2020)
        #expect(custom.hull.lengthOverallMeters == nil)
        #expect(custom.rig.foretriangleHeightMeters == nil)
        #expect(custom.inventory.isEmpty)
        let extasy = try #require(migrated.profile(id: BuiltInVesselID.extasy))
        #expect(extasy.hull.lengthOverallMeters == 11.924)
        #expect(extasy.rig.mainsailLuffMeters == 14.710)
        #expect(extasy.inventory.isEmpty)
        #expect(extasy.id == BuiltInVesselID.extasy)
        let saved = try JSONDecoder().decode(VesselProfileDocument.self, from: Data(contentsOf: url))
        #expect(saved.schemaVersion == 3)
        #expect(saved.profiles.contains { $0.id == customID && $0.name == "Skiff" })

        let negative = VesselProfile(
            id: UUID(),
            name: "Bad",
            constructionYear: 2020,
            origin: .custom,
            performance: .none,
            hull: HullDimensions(lengthOverallMeters: -2)
        )
        let invalid = VesselProfileDocument(schemaVersion: 1, profiles: BuiltInVesselID.seeds + [negative])
        let bytes = try JSONEncoder().encode(invalid)
        try bytes.write(to: url, options: .atomic)
        let rejected = VesselProfileRepository(store: FileVesselProfileStore(directory: directory))
        if case .invalidProfileData = rejected.loadError {} else {
            Issue.record("Expected invalid profile data")
        }
        #expect(try Data(contentsOf: url) == bytes)

        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: url, options: .atomic)
        let damaged = VesselProfileRepository(store: FileVesselProfileStore(directory: directory))
        #expect(damaged.loadError != nil)
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test
    func builtInIdentityStaysProtected() throws {
        let simulator = hullSimulator()
        #expect(throws: VesselProfileStoreError.builtInProfileIsProtected(BuiltInVesselID.extasy)) {
            try simulator.updateCustomVessel(BuiltInVesselID.extasy, metadata: metadata(name: "Renamed", year: 2001, loa: 10))
        }
        let extasy = try #require(simulator.vessels.first { $0.id == BuiltInVesselID.extasy })
        #expect(extasy.name == "Extasy")
        #expect(extasy.hull.lengthOverallMeters == 11.924)
        let session = VesselLibrarySession()
        session.show(BuiltInVesselID.extasy, on: simulator)
        session.buffer.name = "Renamed"
        session.buffer.lengthOverall = "10.000"
        #expect(session.hasUnsavedChanges(in: simulator) == false)
        #expect(session.saveBuffer(on: simulator))
        let protected = try #require(simulator.vessels.first { $0.id == BuiltInVesselID.extasy })
        #expect(protected.name == "Extasy")
        #expect(protected.hull.lengthOverallMeters == 11.924)
    }

    @Test
    func hullAndRigEditsAreDirtyAndSaveDiscardCancelKeepTypedValues() throws {
        let simulator = hullSimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.lengthOverall = "8.200"
        #expect(session.saveBuffer(on: simulator))
        session.buffer.lengthOverall = " 8.200 "
        #expect(session.hasUnsavedChanges(in: simulator) == false)
        session.buffer.lengthOverall = "9.500"
        session.buffer.foretriangleBase = "3.250"
        #expect(session.hasUnsavedChanges(in: simulator))
        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .needsConfirmation)

        #expect(session.resolveUnsavedChanges(.cancel, on: simulator) == .stayed)
        #expect(session.buffer.lengthOverall == "9.500")
        #expect(session.buffer.foretriangleBase == "3.250")
        #expect(simulator.vessels.first { $0.id == custom.id }?.hull.lengthOverallMeters == 8.2)

        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .needsConfirmation)
        #expect(session.resolveUnsavedChanges(.discard, on: simulator) == .perform(.highlight(BuiltInVesselID.nimana)))
        #expect(simulator.vessels.first { $0.id == custom.id }?.rig.foretriangleBaseMeters == nil)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        session.show(custom.id, on: simulator)
        session.buffer.lengthOverall = "9.500"
        session.buffer.mainsailLuff = "12.000"
        #expect(session.requestLeave(.highlight(BuiltInVesselID.extasy), on: simulator) == .needsConfirmation)
        #expect(session.resolveUnsavedChanges(.save, on: simulator) == .perform(.highlight(BuiltInVesselID.extasy)))
        let stored = try #require(simulator.vessels.first { $0.id == custom.id })
        #expect(stored.id == custom.id)
        #expect(stored.hull.lengthOverallMeters == 9.5)
        #expect(stored.rig.mainsailLuffMeters == 12)
        #expect(stored.rig.foretriangleHeightMeters == nil)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func invalidTextAndFailedWritesKeepTheBuffer() throws {
        let store = RejectingHullStore()
        let simulator = hullSimulator(store: store)
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.displacement = "nope"
        #expect(session.saveBuffer(on: simulator) == false)
        #expect(session.buffer.displacement == "nope")
        #expect(session.failureMessage?.contains("number") == true)
        #expect(simulator.vessels.first { $0.id == custom.id }?.hull.displacementKilograms == nil)

        session.buffer.displacement = "2400"
        session.buffer.draft = "0"
        #expect(session.saveBuffer(on: simulator) == false)
        #expect(session.buffer.draft == "0")
        #expect(session.failureMessage?.contains("greater than zero") == true)

        session.buffer.draft = ""
        store.rejectWrites = true
        #expect(session.saveBuffer(on: simulator) == false)
        #expect(session.buffer.displacement == "2400")
        #expect(simulator.vessels.first { $0.id == custom.id }?.hull.displacementKilograms == nil)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func measurementsDoNotChangeSpeedOrTheActiveVessel() throws {
        let extasy = hullTick(profileID: BuiltInVesselID.extasy, mode: .estimated, speed: 4)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs((extasy.speed ?? 0) - polar) < 0.000_001)

        let simulator = hullSimulator()
        let custom = try simulator.createCustomVessel(name: "Skiff")
        try simulator.updateCustomVessel(
            custom.id,
            metadata: metadata(name: "Skiff", year: 2024, loa: 11.924)
        )
        simulator.selectVessel(custom.id)
        let held = hullTick(simulator: simulator, profileID: custom.id, mode: .estimated, speed: 5.5)
        #expect(abs((held.speed ?? 0) - 5.5) < 0.000_001)
        #expect(simulator.boatProfile.hasSpeedPolar == false)
        #expect(simulator.selectedVesselID == custom.id)
        #expect(simulator.vessels.first { $0.id == custom.id }?.performance == VesselProfile.Performance.none)
    }
}

private func metadata(name: String, year: Int?, loa: Double?) -> VesselEditableMetadata {
    VesselEditableMetadata(
        name: name,
        manufacturer: nil,
        modelName: "One",
        constructionYear: year,
        sailNumber: nil,
        registration: nil,
        hull: HullDimensions(lengthOverallMeters: loa),
        rig: RigDimensions()
    )
}

private final class RejectingHullStore: VesselProfileStoring {
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

private func hullSimulator(store: (any VesselProfileStoring)? = nil) -> NMEASimulator {
    let suite = "VesselHull.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return NMEASimulator(userDefaults: defaults, vesselStore: store ?? InMemoryVesselProfileStore())
}

private struct HullTickSample {
    var speed: Double?
}

private func hullTick(profileID: UUID, mode: BoatSpeedMode, speed: Double) -> HullTickSample {
    hullTick(simulator: hullSimulator(), profileID: profileID, mode: mode, speed: speed)
}

private func hullTick(simulator: NMEASimulator, profileID: UUID, mode: BoatSpeedMode, speed: Double) -> HullTickSample {
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.selectVessel(profileID)
    simulator.boatSpeedMode = mode
    simulator.speed = SimulatedValue(type: .speedLog, center: speed, offset: 0, value: speed)
    let time = Date(timeIntervalSince1970: 1_800_006_400)
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
    return HullTickSample(speed: state.vesselTruth.speedThroughWaterKnots)
}
