import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselIdentityTests {

    @Test
    func builtInIdentifiersStayFixed() {
        #expect(BuiltInVesselID.extasy.uuidString == "8F3C1A40-1999-4A07-8E35-4070F1A7E001")
        #expect(BuiltInVesselID.nimana.uuidString == "6B2D4E46-2015-4B46-9C12-46A0B1C2D003")
        let first = VesselProfileRepository(store: InMemoryVesselProfileStore())
        let second = VesselProfileRepository(store: InMemoryVesselProfileStore())
        #expect(first.profile(id: BuiltInVesselID.extasy)?.name == "Extasy")
        #expect(second.profile(id: BuiltInVesselID.extasy)?.id == first.profile(id: BuiltInVesselID.extasy)?.id)
        #expect(first.profile(id: BuiltInVesselID.nimana)?.constructionYear == 2015)
        #expect(first.profile(id: BuiltInVesselID.extasy)?.performance == .farrDesign354)
        #expect(first.profile(id: BuiltInVesselID.nimana)?.performance == VesselProfile.Performance.none)
    }

    @Test
    func customVesselLifecycleDoesNotCopyTheFarrPolar() throws {
        let store = InMemoryVesselProfileStore()
        let repository = VesselProfileRepository(store: store)
        let created = try repository.createCustomVessel(name: "  Tender  ")
        #expect(created.name == "Tender")
        #expect(created.origin == .custom)
        #expect(created.performance == .none)
        #expect(created.id != BuiltInVesselID.extasy)

        try repository.renameVessel(created.id, to: "Tender II")
        #expect(repository.profile(id: created.id)?.name == "Tender II")
        try repository.updateCustomVessel(created.id, name: "Tender II", modelName: "Custom", constructionYear: 2020)
        #expect(repository.profile(id: created.id)?.modelName == "Custom")

        let copy = try repository.duplicateVessel(BuiltInVesselID.extasy)
        #expect(copy.id != BuiltInVesselID.extasy)
        #expect(copy.performance == .none)
        #expect(copy.origin == .custom)

        let reloaded = VesselProfileRepository(store: store)
        #expect(reloaded.profile(id: created.id)?.name == "Tender II")
        #expect(reloaded.profile(id: copy.id)?.performance == VesselProfile.Performance.none)

        try repository.deleteCustomVessel(created.id)
        #expect(repository.profile(id: created.id) == nil)
        #expect(throws: VesselProfileStoreError.builtInProfileIsProtected(BuiltInVesselID.extasy)) {
            try repository.deleteCustomVessel(BuiltInVesselID.extasy)
        }
        #expect(throws: VesselProfileStoreError.builtInProfileIsProtected(BuiltInVesselID.nimana)) {
            try repository.renameVessel(BuiltInVesselID.nimana, to: "Other")
        }
        #expect(throws: VesselProfileStoreError.invalidProfileData("A vessel name is required.")) {
            try repository.createCustomVessel(name: " ")
        }
        #expect(throws: VesselProfileStoreError.missingProfile(created.id)) {
            try repository.renameVessel(created.id, to: "Gone")
        }
    }

    @Test
    func corruptAndUnsupportedFilesAreLeftUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VesselIdentity.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileVesselProfileStore(directory: directory)
        let url = directory.appendingPathComponent(FileVesselProfileStore.fileName)

        let repository = VesselProfileRepository(store: store)
        #expect(repository.loadError == nil)
        #expect(repository.profile(id: BuiltInVesselID.extasy) != nil)

        let garbage = Data("not-json".utf8)
        try garbage.write(to: url, options: .atomic)
        let corrupt = VesselProfileRepository(store: store)
        #expect(corrupt.loadError != nil)
        if case .corruptedPersistenceData = corrupt.loadError {} else {
            Issue.record("Expected corrupted persistence data")
        }
        #expect(try Data(contentsOf: url) == garbage)
        #expect(corrupt.profiles.isEmpty)

        let wrongVersion = """
        {"schemaVersion":99,"profiles":[]}
        """
        try Data(wrongVersion.utf8).write(to: url, options: .atomic)
        let before = try Data(contentsOf: url)
        let unsupported = VesselProfileRepository(store: store)
        if case .unsupportedSchemaVersion(let found, let supported) = unsupported.loadError {
            #expect(found == 99)
            #expect(supported == 3)
        } else {
            Issue.record("Expected an unsupported schema")
        }
        #expect(try Data(contentsOf: url) == before)

        let duplicate = VesselProfileDocument(
            schemaVersion: 1,
            profiles: BuiltInVesselID.seeds + [BuiltInVesselID.seeds[0]]
        )
        try JSONEncoder().encode(duplicate).write(to: url, options: .atomic)
        let duplicated = VesselProfileRepository(store: store)
        #expect(duplicated.loadError == .duplicateIdentifier(BuiltInVesselID.extasy))

        let blank = VesselProfile(
            id: UUID(),
            name: " ",
            modelName: nil,
            constructionYear: nil,
            origin: .custom,
            performance: .none
        )
        let invalid = VesselProfileDocument(schemaVersion: 1, profiles: BuiltInVesselID.seeds + [blank])
        try JSONEncoder().encode(invalid).write(to: url, options: .atomic)
        let invalidLoad = VesselProfileRepository(store: store)
        if case .invalidProfileData = invalidLoad.loadError {} else {
            Issue.record("Expected invalid profile data")
        }
    }

    @Test
    func freshInstallDefaultsToExtasyAndAMissingKeyIsNotAnInvalidSelection() throws {
        let freshDefaults = isolatedVesselDefaults()
        let fresh = NMEASimulator(userDefaults: freshDefaults)
        #expect(fresh.selectedVesselID == BuiltInVesselID.extasy)
        #expect(fresh.boatProfile == .beneteauFirst407)
        #expect(fresh.vesselAllowsSimulation)

        let legacyDefaults = isolatedVesselDefaults()
        let seed = NMEASimulator(userDefaults: legacyDefaults)
        seed.port = 4957
        seed.talkerID = "XY"
        seed.persistLiveSettings()
        let key = "marine_simulator.settings"
        var object = try settingsObject(defaults: legacyDefaults, key: key)
        object.removeValue(forKey: "activeVesselID")
        object.removeValue(forKey: "vesselSelectionWasStored")
        object.removeValue(forKey: "boatProfile")
        legacyDefaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
        let missing = NMEASimulator(userDefaults: legacyDefaults)
        #expect(missing.selectedVesselID == BuiltInVesselID.extasy)
        #expect(missing.port == 4957)
        #expect(missing.talkerID == "XY")
    }

    @Test
    func storedBuiltInUUIDsResolveAndAnUnknownUUIDDoesNotSelectAnotherVessel() throws {
        let defaults = isolatedVesselDefaults()
        let seed = NMEASimulator(userDefaults: defaults)
        seed.port = 4961
        seed.boatSpeedMode = .estimated
        seed.selectVessel(BuiltInVesselID.nimana)
        let restored = NMEASimulator(userDefaults: defaults)
        #expect(restored.selectedVesselID == BuiltInVesselID.nimana)
        #expect(restored.boatProfile.hasSpeedPolar == false)
        #expect(restored.port == 4961)
        #expect(restored.boatSpeedMode == .estimated)

        seed.selectVessel(BuiltInVesselID.extasy)
        let extasy = NMEASimulator(userDefaults: defaults)
        #expect(extasy.selectedVesselID == BuiltInVesselID.extasy)
        #expect(extasy.boatProfile.hasSpeedPolar == true)

        let key = "marine_simulator.settings"
        var object = try settingsObject(defaults: defaults, key: key)
        let missingID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        object["activeVesselID"] = missingID.uuidString
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
        let unresolved = NMEASimulator(userDefaults: defaults)
        #expect(unresolved.selectedVesselID == nil)
        if case .unresolved(let reference) = unresolved.activeVesselState {
            #expect(reference == missingID.uuidString)
        } else {
            Issue.record("Expected unresolved selection")
        }
        #expect(unresolved.port == 4961)
        unresolved.startSimulation()
        #expect(unresolved.isTransmitting == false)
        unresolved.selectVessel(BuiltInVesselID.extasy)
        #expect(unresolved.selectedVesselID == BuiltInVesselID.extasy)
        #expect(unresolved.vesselAllowsSimulation)
    }

    @Test
    func deletingTheActiveCustomVesselRequiresANewSelection() throws {
        let store = InMemoryVesselProfileStore()
        let simulator = NMEASimulator(userDefaults: isolatedVesselDefaults(), vesselStore: store)
        let custom = try simulator.createCustomVessel(name: "Skiff")
        simulator.selectVessel(custom.id)
        #expect(simulator.selectedVesselID == custom.id)
        #expect(simulator.boatProfile.hasSpeedPolar == false)
        let copy = try simulator.duplicateVessel(custom.id)
        #expect(copy.performance == .none)
        try simulator.deleteCustomVessel(custom.id)
        #expect(simulator.selectedVesselID == nil)
        if case .unresolved(let reference) = simulator.activeVesselState {
            #expect(reference == custom.id.uuidString)
        } else {
            Issue.record("Expected unresolved selection after delete")
        }
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.extasy })
        simulator.startSimulation()
        #expect(simulator.isTransmitting == false)
        simulator.selectVessel(copy.id)
        #expect(simulator.selectedVesselID == copy.id)
    }

    @Test
    func legacyBuiltInNamesResolveAndAnUnknownLegacyNameDoesNot() throws {
        let defaults = isolatedVesselDefaults()
        let seed = NMEASimulator(userDefaults: defaults)
        seed.port = 4958
        seed.persistLiveSettings()
        let key = "marine_simulator.settings"
        var object = try settingsObject(defaults: defaults, key: key)
        object.removeValue(forKey: "activeVesselID")
        object.removeValue(forKey: "vesselSelectionWasStored")
        object["boatProfile"] = BoatProfile.nimana.rawValue
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
        let nimana = NMEASimulator(userDefaults: defaults)
        #expect(nimana.selectedVesselID == BuiltInVesselID.nimana)
        #expect(nimana.port == 4958)

        object["boatProfile"] = "retired-vessel"
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
        let retired = NMEASimulator(userDefaults: defaults)
        #expect(retired.selectedVesselID == nil)
        #expect(retired.port == 4958)
        #expect(retired.boatProfile.hasSpeedPolar == false)
    }

    @Test
    func customAndNimanaDoNotUseTheExtasyPolar() {
        let extasy = vesselTick(profileID: BuiltInVesselID.extasy, mode: .estimated, speed: 4)
        let polar = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        #expect(abs((extasy.speed ?? 0) - polar) < 0.000_001)

        let nimana = vesselTick(profileID: BuiltInVesselID.nimana, mode: .estimated, speed: 6.5)
        #expect(abs((nimana.speed ?? 0) - 6.5) < 0.000_001)

        let store = InMemoryVesselProfileStore()
        let simulator = NMEASimulator(userDefaults: isolatedVesselDefaults(), vesselStore: store)
        let custom = try! simulator.createCustomVessel(name: "Skiff")
        let held = vesselTick(simulator: simulator, profileID: custom.id, mode: .estimated, speed: 5)
        #expect(abs((held.speed ?? 0) - 5) < 0.000_001)
        #expect(simulator.boatProfile.hasSpeedPolar == false)

        let manual = vesselTick(profileID: BuiltInVesselID.extasy, mode: .manual, speed: 4)
        #expect(abs((manual.speed ?? 0) - 4) < 0.000_001)
        #expect(abs((manual.gyro ?? 0) - (manual.trueHeading ?? -1)) < 0.000_001)
    }

    @Test
    func aMissingLibrarySeedsExtasyAndACorruptLibraryStaysUnresolved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VesselAudit.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileVesselProfileStore(directory: directory)
        let url = directory.appendingPathComponent(FileVesselProfileStore.fileName)

        let fresh = NMEASimulator(userDefaults: isolatedVesselDefaults(), vesselStore: store)
        #expect(fresh.selectedVesselID == BuiltInVesselID.extasy)
        #expect(fresh.vesselAllowsSimulation)
        #expect(fresh.activeVesselName == "Extasy")
        #expect(FileManager.default.fileExists(atPath: url.path))

        let garbage = Data("{".utf8)
        try garbage.write(to: url, options: .atomic)
        let defaults = isolatedVesselDefaults()
        let seed = NMEASimulator(userDefaults: defaults, vesselStore: InMemoryVesselProfileStore())
        seed.selectVessel(BuiltInVesselID.extasy)
        seed.port = 4971
        let corrupt = NMEASimulator(userDefaults: defaults, vesselStore: store)
        #expect(corrupt.selectedVesselID == nil)
        #expect(corrupt.vesselStoreError != nil)
        #expect(corrupt.vesselAllowsSimulation == false)
        #expect(corrupt.activeVesselName == "No vessel")
        #expect(corrupt.activeVesselSummary.contains("left in place"))
        if case .unresolved(let reference) = corrupt.activeVesselState {
            #expect(reference == BuiltInVesselID.extasy.uuidString)
        } else {
            Issue.record("Expected the stored Extasy reference to stay unresolved")
        }
        #expect(try Data(contentsOf: url) == garbage)
        #expect(corrupt.port == 4971)
        corrupt.startSimulation()
        #expect(corrupt.isTransmitting == false)
        corrupt.beginManeuver(.tack(.port))
        #expect(corrupt.maneuverRejectionReason == "Select a vessel before starting a maneuver.")
        corrupt.runSimulationCycle(at: Date(timeIntervalSince1970: 1_800_006_100))
        #expect(corrupt.isTransmitting == false)
    }

    @Test
    func switchingVesselsUsesTheNextSnapshotAndDoesNotCarryTheFarrTable() throws {
        let store = InMemoryVesselProfileStore()
        let simulator = preparedVesselSimulator(store: store)
        let custom = try simulator.createCustomVessel(name: "Skiff")
        let polarAt90 = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 90) ?? -1
        let polarAt60 = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 60) ?? -1
        #expect(abs(polarAt90 - polarAt60) > 0.2)

        let time = Date(timeIntervalSince1970: 1_800_006_200)
        installTransmitRuntime(on: simulator, at: time, speed: 4)
        simulator.selectVessel(BuiltInVesselID.extasy)
        simulator.runSimulationCycle(at: time)
        let extasySpeed = simulator.transmitRuntime?.vesselTruth.speedThroughWaterKnots ?? -1
        #expect(abs(extasySpeed - polarAt90) < 0.000_001)

        simulator.transmitRuntime?.activeManeuver = ActiveManeuver(
            kind: .tack,
            side: .port,
            startedAt: time,
            duration: 8,
            fromTrueHeading: 90,
            toTrueHeading: 270,
            trueWindDirection: 180,
            turnDelta: 180,
            drivesHeading: true
        )
        simulator.selectVessel(custom.id)
        simulator.twd = SimulatedValue(type: .windDirection, center: 150, offset: 0, value: 150)
        let switched = time.addingTimeInterval(0.05)
        simulator.runSimulationCycle(at: switched)
        #expect(simulator.boatProfile.hasSpeedPolar == false)
        #expect(simulator.selectedVesselID == custom.id)
        let held = simulator.transmitRuntime?.vesselTruth.speedThroughWaterKnots ?? -1
        #expect(abs(held - extasySpeed) < 0.000_001)
        #expect(abs(held - polarAt60) > 0.2)
        #expect(simulator.transmitRuntime?.activeManeuver?.toTrueHeading == 270)

        let heading = simulator.transmitRuntime?.vesselTruth.trueHeading ?? 0
        let wind = simulator.transmitRuntime?.twd.value ?? 150
        let angle = abs(calculateShortestRotation(from: heading, to: wind))
        let expected = BoatProfile.beneteauFirst407.estimatedBoatSpeed(
            trueWindSpeedKnots: 12,
            trueWindAngleDegrees: angle
        ) ?? -1
        simulator.transmitRuntime?.activeManeuver = nil
        simulator.selectVessel(BuiltInVesselID.extasy)
        simulator.runSimulationCycle(at: switched.addingTimeInterval(0.05))
        #expect(simulator.boatProfile.hasSpeedPolar)
        #expect(abs((simulator.transmitRuntime?.vesselTruth.speedThroughWaterKnots ?? -1) - expected) < 0.000_001)
    }

    @Test
    func deletingTheActiveVesselWhileTransmittingStopsAndBlocksTheNextTick() throws {
        let store = InMemoryVesselProfileStore()
        let simulator = preparedVesselSimulator(store: store)
        let custom = try simulator.createCustomVessel(name: "Skiff")
        simulator.selectVessel(custom.id)
        simulator.boatSpeedMode = .estimated
        simulator.isTimerSelected = true
        simulator.startSimulation()
        #expect(simulator.isTransmitting)

        try simulator.deleteCustomVessel(custom.id)
        #expect(simulator.isTransmitting == false)
        #expect(simulator.selectedVesselID == nil)
        if case .unresolved(let reference) = simulator.activeVesselState {
            #expect(reference == custom.id.uuidString)
        } else {
            Issue.record("Expected the deleted id to stay unresolved")
        }
        #expect(simulator.activeVesselSummary.contains(custom.id.uuidString))
        let speed = simulator.speed.value
        let messages = simulator.outputMessages.count
        simulator.runSimulationCycle(at: Date(timeIntervalSince1970: 1_800_006_300))
        #expect(simulator.speed.value == speed)
        #expect(simulator.outputMessages.count == messages)
        #expect(simulator.isTransmitting == false)
        simulator.beginManeuver(.gybe(.starboard))
        #expect(simulator.maneuverRejectionReason == "Select a vessel before starting a maneuver.")
        #expect(simulator.activeManeuver == nil)

        #expect(throws: VesselProfileStoreError.builtInProfileIsProtected(BuiltInVesselID.extasy)) {
            try simulator.deleteCustomVessel(BuiltInVesselID.extasy)
        }
        simulator.selectVessel(BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.nimana)
        #expect(simulator.boatProfile.hasSpeedPolar == false)
        #expect(simulator.vesselAllowsSimulation)
    }

    @Test
    func aCustomRecordCannotClaimABuiltInIdentityAndTicksDoNotSaveTheLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VesselAudit.identity.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileVesselProfileStore(directory: directory)
        let url = directory.appendingPathComponent(FileVesselProfileStore.fileName)
        _ = VesselProfileRepository(store: store)
        let before = try Data(contentsOf: url)

        let impostor = VesselProfile(
            id: BuiltInVesselID.extasy,
            name: "Extasy",
            modelName: "Beneteau First 40.7",
            constructionYear: 1999,
            origin: .custom,
            performance: .farrDesign354
        )
        let forged = VesselProfileDocument(schemaVersion: 1, profiles: [impostor, BuiltInVesselID.seeds[1]])
        try JSONEncoder().encode(forged).write(to: url, options: .atomic)
        let forgedBytes = try Data(contentsOf: url)
        let rejected = VesselProfileRepository(store: store)
        #expect(rejected.loadError == .duplicateIdentifier(BuiltInVesselID.extasy))
        #expect(rejected.profiles.isEmpty)
        #expect(try Data(contentsOf: url) == forgedBytes)

        let counting = SaveCountingVesselStore()
        let simulator = preparedVesselSimulator(store: counting)
        #expect(counting.saves == 1)
        simulator.selectVessel(BuiltInVesselID.nimana)
        let time = Date(timeIntervalSince1970: 1_800_006_400)
        simulator.runSimulationCycle(at: time)
        simulator.runSimulationCycle(at: time.addingTimeInterval(0.05))
        simulator.runSimulationCycle(at: time.addingTimeInterval(0.10))
        #expect(counting.saves == 1)
        _ = try simulator.createCustomVessel(name: "Skiff")
        #expect(counting.saves == 2)
        #expect(before != forgedBytes)
    }
}

private func settingsObject(defaults: UserDefaults, key: String) throws -> [String: Any] {
    let data = try #require(defaults.data(forKey: key))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private struct VesselTickSample {
    var speed: Double?
    var gyro: Double?
    var trueHeading: Double?
}

private func isolatedVesselDefaults() -> UserDefaults {
    let suite = "VesselIdentity.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private final class SaveCountingVesselStore: VesselProfileStoring {
    private var document: VesselProfileDocument?
    private(set) var saves = 0

    func loadDocument() throws -> VesselProfileDocument? {
        document
    }

    func saveDocument(_ document: VesselProfileDocument) throws {
        saves += 1
        self.document = document
    }
}

private func preparedVesselSimulator(store: any VesselProfileStoring) -> NMEASimulator {
    let simulator = NMEASimulator(userDefaults: isolatedVesselDefaults(), vesselStore: store)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.isTimerSelected = false
    simulator.weatherSourceMode = .manual
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    simulator.sensorToggles.hasAnemometer = true
    simulator.sensorToggles.hasSpeedLog = true
    simulator.boatSpeedMode = .estimated
    simulator.twd = SimulatedValue(type: .windDirection, center: 180, offset: 0, value: 180)
    simulator.tws = SimulatedValue(type: .windSpeed, center: 12, offset: 0, value: 12)
    simulator.gyroHeading = SimulatedValue(type: .gyroCompass, center: 90, offset: 0, value: 90)
    let variation = SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: Date(timeIntervalSince1970: 1_800_006_200))
    let magnetic = normalizeAngle(90 - variation)
    simulator.heading = SimulatedValue(type: .magneticCompass, center: magnetic, offset: 0, value: magnetic)
    simulator.speed = SimulatedValue(type: .speedLog, center: 4, offset: 0, value: 4)
    return simulator
}

private func installTransmitRuntime(on simulator: NMEASimulator, at time: Date, speed: Double) {
    var runtime = SimulationState(from: simulator)
    runtime.lastSensorEvolutionDate = time
    runtime.lastSimulationTickDate = time.addingTimeInterval(-0.05)
    runtime.speed.value = speed
    runtime.vesselTruth.speedThroughWaterKnots = speed
    runtime.vesselTruth.trueHeading = 90
    simulator.transmitRuntime = runtime
}

private func vesselTick(profileID: UUID, mode: BoatSpeedMode, speed: Double) -> VesselTickSample {
    vesselTick(simulator: NMEASimulator(userDefaults: isolatedVesselDefaults()), profileID: profileID, mode: mode, speed: speed)
}

private func vesselTick(simulator: NMEASimulator, profileID: UUID, mode: BoatSpeedMode, speed: Double) -> VesselTickSample {
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
    let time = Date(timeIntervalSince1970: 1_800_006_000)
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
    return VesselTickSample(
        speed: state.vesselTruth.speedThroughWaterKnots,
        gyro: state.gyroHeading.value,
        trueHeading: state.vesselTruth.trueHeading
    )
}
