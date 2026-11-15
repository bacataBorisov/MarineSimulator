import Foundation

/// UI-independent vessel library. The simulation tick does not call it.
final class VesselProfileRepository {
    private let store: any VesselProfileStoring
    private(set) var document: VesselProfileDocument?
    private(set) var loadError: VesselProfileStoreError?

    var profiles: [VesselProfile] { document?.profiles ?? [] }

    init(store: any VesselProfileStoring) {
        self.store = store
        do {
            guard let loaded = try store.loadDocument() else {
                let seeded = VesselProfileDocument.seeded()
                try store.saveDocument(seeded)
                document = seeded
                return
            }
            let validated = try Self.validated(loaded)
            if validated != loaded {
                try store.saveDocument(validated)
            }
            document = validated
        } catch let error as VesselProfileStoreError {
            loadError = error
            document = nil
        } catch {
            loadError = .readFailure(error.localizedDescription)
            document = nil
        }
    }

    func profile(id: UUID) -> VesselProfile? {
        profiles.first { $0.id == id }
    }

    @discardableResult
    func createCustomVessel(name: String, modelName: String? = nil, constructionYear: Int? = nil) throws -> VesselProfile {
        try ensureWritable()
        guard var proposed = document else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VesselProfileStoreError.invalidProfileData("A vessel name is required.")
        }
        let profile = VesselProfile(
            id: UUID(),
            name: trimmed,
            modelName: modelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            constructionYear: constructionYear,
            origin: .custom,
            performance: .none
        )
        try Self.validateCustomProfile(profile)
        proposed.profiles.append(profile)
        try commit(proposed)
        return profile
    }

    func updateCustomVessel(_ id: UUID, metadata: VesselEditableMetadata) throws {
        try ensureWritable()
        guard var proposed = document else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
        guard let index = proposed.profiles.firstIndex(where: { $0.id == id }) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        guard proposed.profiles[index].origin == .custom else {
            throw VesselProfileStoreError.builtInProfileIsProtected(id)
        }
        let trimmed = metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        proposed.profiles[index].name = trimmed
        proposed.profiles[index].manufacturer = metadata.manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        proposed.profiles[index].modelName = metadata.modelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        proposed.profiles[index].constructionYear = metadata.constructionYear
        proposed.profiles[index].sailNumber = metadata.sailNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        proposed.profiles[index].registration = metadata.registration?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        proposed.profiles[index].hull = metadata.hull
        proposed.profiles[index].rig = metadata.rig
        proposed.profiles[index].id = id
        proposed.profiles[index].origin = .custom
        proposed.profiles[index].performance = .none
        try Self.validateCustomProfile(proposed.profiles[index])
        try commit(proposed)
    }

    func updateCustomVessel(_ id: UUID, name: String, modelName: String?, constructionYear: Int?) throws {
        guard let existing = profile(id: id) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        try updateCustomVessel(
            id,
            metadata: VesselEditableMetadata(
                name: name,
                manufacturer: existing.manufacturer,
                modelName: modelName,
                constructionYear: constructionYear,
                sailNumber: existing.sailNumber,
                registration: existing.registration,
                hull: existing.hull,
                rig: existing.rig
            )
        )
    }

    func renameVessel(_ id: UUID, to name: String) throws {
        guard let profile = profile(id: id) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        try updateCustomVessel(id, name: name, modelName: profile.modelName, constructionYear: profile.constructionYear)
    }

    @discardableResult
    func duplicateVessel(_ id: UUID) throws -> VesselProfile {
        try ensureWritable()
        guard let source = profile(id: id) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        guard var proposed = document else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
        let remapped = Self.remappedInventory(source.inventory, active: source.activeSails)
        let copy = VesselProfile(
            id: UUID(),
            name: "\(source.name) Copy",
            modelName: source.modelName,
            constructionYear: source.constructionYear,
            origin: .custom,
            performance: .none,
            manufacturer: source.manufacturer,
            sailNumber: source.sailNumber,
            registration: source.registration,
            hull: source.hull,
            rig: source.rig,
            inventory: remapped.inventory,
            activeSails: remapped.active
        )
        proposed.profiles.append(copy)
        try commit(proposed)
        return copy
    }

    func deleteCustomVessel(_ id: UUID) throws {
        try ensureWritable()
        guard var proposed = document else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
        guard let profile = proposed.profiles.first(where: { $0.id == id }) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        guard profile.origin == .custom else {
            throw VesselProfileStoreError.builtInProfileIsProtected(id)
        }
        proposed.profiles.removeAll { $0.id == id }
        try commit(proposed)
    }

    private func ensureWritable() throws {
        if let loadError {
            throw loadError
        }
        guard document != nil else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
    }

    /// Saves the proposed library, then adopts it. A failed write leaves the current library in place.
    private func commit(_ proposed: VesselProfileDocument) throws {
        do {
            try store.saveDocument(proposed)
        } catch let error as VesselProfileStoreError {
            throw error
        } catch {
            throw VesselProfileStoreError.writeFailure(error.localizedDescription)
        }
        document = proposed
    }

    static func validated(_ document: VesselProfileDocument) throws -> VesselProfileDocument {
        guard (VesselProfileDocument.minimumReadableSchemaVersion...VesselProfileDocument.currentSchemaVersion)
            .contains(document.schemaVersion) else {
            throw VesselProfileStoreError.unsupportedSchemaVersion(
                found: document.schemaVersion,
                supported: VesselProfileDocument.currentSchemaVersion
            )
        }
        var seen = Set<UUID>()
        for profile in document.profiles where !seen.insert(profile.id).inserted {
            throw VesselProfileStoreError.duplicateIdentifier(profile.id)
        }
        let customs = document.profiles.filter { $0.origin != .builtIn }
        for profile in customs {
            if BuiltInVesselID.all.contains(profile.id) {
                throw VesselProfileStoreError.duplicateIdentifier(profile.id)
            }
            try validateCustomProfile(profile)
        }
        let loadedBuiltIns = Dictionary(uniqueKeysWithValues: document.profiles.filter { $0.origin == .builtIn }.map { ($0.id, $0) })
        let builtIns = try BuiltInVesselID.seeds.map { seed -> VesselProfile in
            var merged = seed
            if let stored = loadedBuiltIns[seed.id] {
                if stored.inventoryIncludedInFile {
                    merged.inventory = stored.inventory
                    merged.activeSails = stored.activeSails
                } else {
                    merged.inventory = []
                    merged.activeSails = ActiveSailSelection()
                }
            }
            merged.inventoryIncludedInFile = true
            try validateEquipment(merged)
            return merged
        }
        let profiles = builtIns + customs
        try validateSailIdentifiers(profiles)
        return VesselProfileDocument(
            schemaVersion: VesselProfileDocument.currentSchemaVersion,
            profiles: profiles
        )
    }

    func saveProfileEdits(_ id: UUID, metadata: VesselEditableMetadata?, inventory: [SailRecord]) throws {
        try ensureWritable()
        guard var proposed = document else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
        guard let index = proposed.profiles.firstIndex(where: { $0.id == id }) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        if let metadata {
            guard proposed.profiles[index].origin == .custom else {
                throw VesselProfileStoreError.builtInProfileIsProtected(id)
            }
            proposed.profiles[index].name = metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
            proposed.profiles[index].manufacturer = metadata.manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            proposed.profiles[index].modelName = metadata.modelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            proposed.profiles[index].constructionYear = metadata.constructionYear
            proposed.profiles[index].sailNumber = metadata.sailNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            proposed.profiles[index].registration = metadata.registration?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            proposed.profiles[index].hull = metadata.hull
            proposed.profiles[index].rig = metadata.rig
            proposed.profiles[index].origin = .custom
            proposed.profiles[index].performance = .none
        }
        proposed.profiles[index].id = id
        proposed.profiles[index].inventory = inventory
        proposed.profiles[index].activeSails = proposed.profiles[index].activeSails.clearingSails(absentFrom: inventory)
        proposed.profiles[index].inventoryIncludedInFile = true
        if proposed.profiles[index].origin == .custom {
            try Self.validateCustomProfile(proposed.profiles[index])
        } else {
            try Self.validateEquipment(proposed.profiles[index])
        }
        try Self.validateSailIdentifiers(proposed.profiles)
        try commit(proposed)
    }

    func replaceActiveSails(_ id: UUID, with selection: ActiveSailSelection) throws {
        try ensureWritable()
        guard var proposed = document else {
            throw VesselProfileStoreError.corruptedPersistenceData("Vessel profiles are not loaded.")
        }
        guard let index = proposed.profiles.firstIndex(where: { $0.id == id }) else {
            throw VesselProfileStoreError.missingProfile(id)
        }
        proposed.profiles[index].activeSails = selection
        try Self.validateEquipment(proposed.profiles[index])
        try commit(proposed)
    }

    static func remappedInventory(
        _ inventory: [SailRecord],
        active: ActiveSailSelection
    ) -> (inventory: [SailRecord], active: ActiveSailSelection) {
        var map: [UUID: UUID] = [:]
        let copies = inventory.map { sail in
            var copy = sail
            let newID = UUID()
            map[sail.id] = newID
            copy.id = newID
            return copy
        }
        var selection = active
        selection.mainsailID = selection.mainsailID.flatMap { map[$0] }
        selection.headsailID = selection.headsailID.flatMap { map[$0] }
        selection.downwindSailID = selection.downwindSailID.flatMap { map[$0] }
        return (copies, selection)
    }

    static func validateCustomProfile(_ profile: VesselProfile) throws {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VesselProfileStoreError.invalidProfileData("A vessel name is required.")
        }
        if profile.performance != .none {
            throw VesselProfileStoreError.invalidProfileData("A custom vessel cannot carry a built-in polar.")
        }
        if let year = profile.constructionYear, !(1800...2100).contains(year) {
            throw VesselProfileStoreError.invalidProfileData("Construction year must be from 1800 through 2100.")
        }
        try requirePositive(profile.hull.lengthOverallMeters, "Length overall")
        try requirePositive(profile.hull.waterlineLengthMeters, "Waterline length")
        try requirePositive(profile.hull.beamMeters, "Beam")
        try requirePositive(profile.hull.draftMeters, "Draft")
        try requirePositive(profile.hull.displacementKilograms, "Displacement")
        try requirePositive(profile.rig.foretriangleHeightMeters, "I")
        try requirePositive(profile.rig.foretriangleBaseMeters, "J")
        try requirePositive(profile.rig.mainsailLuffMeters, "P")
        try requirePositive(profile.rig.mainsailFootMeters, "E")
        try validateEquipment(profile)
    }

    static func validateEquipment(_ profile: VesselProfile) throws {
        var seen = Set<UUID>()
        for sail in profile.inventory {
            if !seen.insert(sail.id).inserted {
                throw VesselProfileStoreError.duplicateIdentifier(sail.id)
            }
            try validateSail(sail)
        }
        try validateActiveSails(profile.activeSails, inventory: profile.inventory)
    }

    static func validateSailIdentifiers(_ profiles: [VesselProfile]) throws {
        var seen = Set<UUID>()
        for profile in profiles {
            for sail in profile.inventory where !seen.insert(sail.id).inserted {
                throw VesselProfileStoreError.duplicateIdentifier(sail.id)
            }
        }
    }

    private static func validateSail(_ sail: SailRecord) throws {
        if sail.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VesselProfileStoreError.invalidProfileData("A sail name is required.")
        }
        if let year = sail.constructionYear, !(1800...2100).contains(year) {
            throw VesselProfileStoreError.invalidProfileData("Sail construction year must be from 1800 through 2100.")
        }
        switch sail.category {
        case .mainsail:
            guard sail.headsail == nil, sail.downwind == nil, sail.general == nil else {
                throw VesselProfileStoreError.invalidProfileData("A mainsail stores only mainsail measurements.")
            }
            try validateMainsail(sail.mainsail)
        case .headsail:
            guard sail.mainsail == nil, sail.downwind == nil, sail.general == nil else {
                throw VesselProfileStoreError.invalidProfileData("A headsail stores only headsail measurements.")
            }
            try validateHeadsail(sail.headsail)
        case .symmetricSpinnaker, .asymmetricSpinnaker:
            guard sail.mainsail == nil, sail.headsail == nil, sail.general == nil else {
                throw VesselProfileStoreError.invalidProfileData("A downwind sail stores only downwind measurements.")
            }
            try validateDownwind(sail.downwind)
        case .codeSail, .other:
            guard sail.mainsail == nil, sail.headsail == nil, sail.downwind == nil else {
                throw VesselProfileStoreError.invalidProfileData("This sail stores only luff, leech, foot, and area.")
            }
            try validateGeneral(sail.general)
        }
    }

    private static func validateMainsail(_ measurements: MainsailMeasurements?) throws {
        guard let measurements else { return }
        try requirePositive(measurements.luffMeters, "Sail luff")
        try requirePositive(measurements.leechMeters, "Sail leech")
        try requirePositive(measurements.footMeters, "Sail foot")
        try requirePositive(measurements.areaSquareMeters, "Sail area")
        if let reefCount = measurements.reefCount, !(0...3).contains(reefCount) {
            throw VesselProfileStoreError.invalidProfileData("Reef count must be from 0 through 3.")
        }
    }

    private static func validateHeadsail(_ measurements: HeadsailMeasurements?) throws {
        guard let measurements else { return }
        try requirePositive(measurements.luffMeters, "Sail luff")
        try requirePositive(measurements.leechMeters, "Sail leech")
        try requirePositive(measurements.footMeters, "Sail foot")
        try requirePositive(measurements.luffPerpendicularMeters, "LP")
        try requirePositive(measurements.areaSquareMeters, "Sail area")
    }

    private static func validateDownwind(_ measurements: DownwindMeasurements?) throws {
        guard let measurements else { return }
        try requirePositive(measurements.luffMeters, "SLU")
        try requirePositive(measurements.leechMeters, "SLE")
        try requirePositive(measurements.footMeters, "SF")
        try requirePositive(measurements.halfWidthMeters, "SHW")
        try requirePositive(measurements.areaSquareMeters, "Sail area")
    }

    private static func validateGeneral(_ measurements: GeneralSailMeasurements?) throws {
        guard let measurements else { return }
        try requirePositive(measurements.luffMeters, "Sail luff")
        try requirePositive(measurements.leechMeters, "Sail leech")
        try requirePositive(measurements.footMeters, "Sail foot")
        try requirePositive(measurements.areaSquareMeters, "Sail area")
    }

    static func validateActiveSails(_ selection: ActiveSailSelection, inventory: [SailRecord]) throws {
        let byID = Dictionary(uniqueKeysWithValues: inventory.map { ($0.id, $0) })
        func sail(_ id: UUID?, slot: String, allows: (SailCategory) -> Bool) throws -> SailRecord? {
            guard let id else { return nil }
            guard let sail = byID[id] else {
                throw VesselProfileStoreError.invalidProfileData("\(slot) refers to a sail that is not on this vessel.")
            }
            guard allows(sail.category) else {
                throw VesselProfileStoreError.invalidProfileData("\(sail.name) cannot fill the \(slot) slot.")
            }
            return sail
        }
        let main = try sail(selection.mainsailID, slot: "Mainsail", allows: { $0.fitsMainsailSlot })
        _ = try sail(selection.headsailID, slot: "Headsail", allows: { $0.fitsHeadsailSlot })
        _ = try sail(selection.downwindSailID, slot: "Downwind", allows: { $0.fitsDownwindSlot })
        let chosen = [selection.mainsailID, selection.headsailID, selection.downwindSailID].compactMap { $0 }
        if Set(chosen).count != chosen.count {
            throw VesselProfileStoreError.invalidProfileData("One sail cannot fill two active slots.")
        }
        if main == nil, selection.mainsailReef != .full {
            throw VesselProfileStoreError.invalidProfileData("A reef requires a selected mainsail.")
        }
        if let count = main?.mainsail?.reefCount {
            let used: Int
            switch selection.mainsailReef {
            case .full: used = 0
            case .reef1: used = 1
            case .reef2: used = 2
            case .reef3: used = 3
            }
            if used > count {
                throw VesselProfileStoreError.invalidProfileData("This mainsail does not have that reef.")
            }
        }
    }

    private static func requirePositive(_ value: Double?, _ label: String) throws {
        guard let value else { return }
        guard value.isFinite, value > 0 else {
            throw VesselProfileStoreError.invalidProfileData("\(label) must be greater than zero.")
        }
    }
}

final class InMemoryVesselProfileStore: VesselProfileStoring {
    private var document: VesselProfileDocument?

    func loadDocument() throws -> VesselProfileDocument? {
        document
    }

    func saveDocument(_ document: VesselProfileDocument) throws {
        self.document = document
    }
}

/// JSON file under Application Support. Writes are atomic. A failed read does not replace the file.
final class FileVesselProfileStore: VesselProfileStoring {
    static let fileName = "vessel-profiles.json"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func applicationSupport() -> FileVesselProfileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return FileVesselProfileStore(directory: base.appendingPathComponent("MarineSimulator", isDirectory: true))
    }

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    func loadDocument() throws -> VesselProfileDocument? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VesselProfileStoreError.readFailure(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(VesselProfileDocument.self, from: data)
        } catch {
            throw VesselProfileStoreError.corruptedPersistenceData(error.localizedDescription)
        }
    }

    func saveDocument(_ document: VesselProfileDocument) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as VesselProfileStoreError {
            throw error
        } catch {
            throw VesselProfileStoreError.writeFailure(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
