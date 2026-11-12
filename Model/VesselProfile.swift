import Foundation

/// Stable ids for the two seeded research vessels. These values are the persistent identity.
/// Do not generate them at launch.
enum BuiltInVesselID {
    static let extasy = UUID(uuidString: "8F3C1A40-1999-4A07-8E35-4070F1A7E001")!
    static let nimana = UUID(uuidString: "6B2D4E46-2015-4B46-9C12-46A0B1C2D003")!

    static var all: Set<UUID> { [extasy, nimana] }

    static var seeds: [VesselProfile] {
        [
            VesselProfile(
                id: extasy,
                name: "Extasy",
                modelName: "Beneteau First 40.7",
                constructionYear: 1999,
                origin: .builtIn,
                performance: .farrDesign354,
                manufacturer: "Beneteau",
                sailNumber: "ITA-13903",
                hull: HullDimensions(
                    lengthOverallMeters: 11.924,
                    beamMeters: 3.770,
                    draftMeters: 2.425,
                    displacementKilograms: 7_272
                ),
                rig: RigDimensions(
                    foretriangleBaseMeters: 4.420,
                    mainsailLuffMeters: 14.710,
                    mainsailFootMeters: 5.370
                ),
                inventory: ReferenceSails.extasy
            ),
            VesselProfile(
                id: nimana,
                name: "Nimana",
                modelName: "Bavaria Cruiser 46",
                constructionYear: 2015,
                origin: .builtIn,
                performance: .none,
                manufacturer: "Bavaria",
                sailNumber: "BUL 46",
                hull: HullDimensions(
                    lengthOverallMeters: 13.600,
                    beamMeters: 4.352,
                    draftMeters: 2.108,
                    displacementKilograms: 12_888
                ),
                rig: RigDimensions(
                    foretriangleBaseMeters: 5.510,
                    mainsailLuffMeters: 16.550,
                    mainsailFootMeters: 5.450
                ),
                inventory: ReferenceSails.nimana
            )
        ]
    }
}

enum ActiveVesselState: Equatable, Sendable {
    case resolved(UUID)
    case unresolved(storedReference: String)
}

struct HullDimensions: Codable, Equatable, Sendable {
    /// Length overall, metres. Nil means unknown.
    var lengthOverallMeters: Double?
    /// Waterline length, metres. Nil means unknown.
    var waterlineLengthMeters: Double?
    /// Maximum beam, metres. Nil means unknown.
    var beamMeters: Double?
    /// Draft, metres. Nil means unknown.
    var draftMeters: Double?
    /// Lightship displacement, kilograms. Nil means unknown.
    var displacementKilograms: Double?

    init(
        lengthOverallMeters: Double? = nil,
        waterlineLengthMeters: Double? = nil,
        beamMeters: Double? = nil,
        draftMeters: Double? = nil,
        displacementKilograms: Double? = nil
    ) {
        self.lengthOverallMeters = lengthOverallMeters
        self.waterlineLengthMeters = waterlineLengthMeters
        self.beamMeters = beamMeters
        self.draftMeters = draftMeters
        self.displacementKilograms = displacementKilograms
    }
}

struct RigDimensions: Codable, Equatable, Sendable {
    /// I, foretriangle height, metres. Nil means unknown.
    var foretriangleHeightMeters: Double?
    /// J, foretriangle base, metres. Nil means unknown.
    var foretriangleBaseMeters: Double?
    /// P, mainsail luff, metres. Nil means unknown.
    var mainsailLuffMeters: Double?
    /// E, mainsail foot, metres. Nil means unknown.
    var mainsailFootMeters: Double?

    init(
        foretriangleHeightMeters: Double? = nil,
        foretriangleBaseMeters: Double? = nil,
        mainsailLuffMeters: Double? = nil,
        mainsailFootMeters: Double? = nil
    ) {
        self.foretriangleHeightMeters = foretriangleHeightMeters
        self.foretriangleBaseMeters = foretriangleBaseMeters
        self.mainsailLuffMeters = mainsailLuffMeters
        self.mainsailFootMeters = mainsailFootMeters
    }
}

struct VesselEditableMetadata: Equatable, Sendable {
    var name: String
    var manufacturer: String?
    var modelName: String?
    var constructionYear: Int?
    var sailNumber: String?
    var registration: String?
    var hull: HullDimensions
    var rig: RigDimensions
}

struct VesselProfile: Codable, Equatable, Identifiable, Sendable {
    enum Origin: String, Codable, Equatable, Sendable {
        case builtIn
        case custom
    }

    /// Speed model attached to a vessel. Only the Extasy seed carries the Farr table.
    /// A custom vessel, including a duplicate of Extasy, stays `.none`.
    enum Performance: String, Codable, Equatable, Sendable {
        case farrDesign354
        case none
    }

    var id: UUID
    var name: String
    var manufacturer: String?
    var modelName: String?
    var constructionYear: Int?
    var sailNumber: String?
    /// Optional national registration or other identifier. Nil means not recorded.
    var registration: String?
    var origin: Origin
    var performance: Performance
    var hull: HullDimensions
    var rig: RigDimensions
    var inventory: [SailRecord]
    var activeSails: ActiveSailSelection
    /// False when an older file omitted the inventory key. Missing inventory stays empty.
    var inventoryIncludedInFile: Bool

    init(
        id: UUID,
        name: String,
        modelName: String? = nil,
        constructionYear: Int? = nil,
        origin: Origin,
        performance: Performance,
        manufacturer: String? = nil,
        sailNumber: String? = nil,
        registration: String? = nil,
        hull: HullDimensions = HullDimensions(),
        rig: RigDimensions = RigDimensions(),
        inventory: [SailRecord] = [],
        activeSails: ActiveSailSelection = ActiveSailSelection(),
        inventoryIncludedInFile: Bool = true
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.constructionYear = constructionYear
        self.sailNumber = sailNumber
        self.registration = registration
        self.origin = origin
        self.performance = performance
        self.hull = hull
        self.rig = rig
        self.inventory = inventory
        self.activeSails = activeSails
        self.inventoryIncludedInFile = inventoryIncludedInFile
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, manufacturer, modelName, constructionYear, sailNumber, registration
        case origin, performance, hull, rig, inventory, activeSails
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        constructionYear = try container.decodeIfPresent(Int.self, forKey: .constructionYear)
        sailNumber = try container.decodeIfPresent(String.self, forKey: .sailNumber)
        registration = try container.decodeIfPresent(String.self, forKey: .registration)
        origin = try container.decode(Origin.self, forKey: .origin)
        performance = try container.decode(Performance.self, forKey: .performance)
        hull = try container.decodeIfPresent(HullDimensions.self, forKey: .hull) ?? HullDimensions()
        rig = try container.decodeIfPresent(RigDimensions.self, forKey: .rig) ?? RigDimensions()
        if container.contains(.inventory) {
            inventory = try container.decode([SailRecord].self, forKey: .inventory)
            inventoryIncludedInFile = true
        } else {
            inventory = []
            inventoryIncludedInFile = false
        }
        activeSails = try container.decodeIfPresent(ActiveSailSelection.self, forKey: .activeSails) ?? ActiveSailSelection()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(manufacturer, forKey: .manufacturer)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encodeIfPresent(constructionYear, forKey: .constructionYear)
        try container.encodeIfPresent(sailNumber, forKey: .sailNumber)
        try container.encodeIfPresent(registration, forKey: .registration)
        try container.encode(origin, forKey: .origin)
        try container.encode(performance, forKey: .performance)
        try container.encode(hull, forKey: .hull)
        try container.encode(rig, forKey: .rig)
        try container.encode(inventory, forKey: .inventory)
        try container.encode(activeSails, forKey: .activeSails)
    }

    var summary: String {
        switch (origin, performance) {
        case (.builtIn, .farrDesign354):
            return "Beneteau First 40.7 (1999). Speed grid and optima from the Farr Design #354 manufacturer prediction."
        case (.builtIn, .none):
            return "Bavaria Cruiser 46 (2015). Polar is pending integration. From Wind holds the current boat speed."
        case (.custom, _):
            return "Custom vessel. No polar is configured. From Wind holds the current boat speed."
        }
    }

    /// Polar table used by the existing engine. Nil means this vessel must not borrow another boat's polar.
    var speedPolar: BoatProfile? {
        switch performance {
        case .farrDesign354:
            return .beneteauFirst407
        case .none:
            return nil
        }
    }

    /// Sailing-band key for the existing maneuver policy. A vessel without a speed polar uses the no-polar bands.
    var sailingKey: BoatProfile {
        speedPolar ?? .nimana
    }
}

struct VesselProfileDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3
    static let minimumReadableSchemaVersion = 1

    var schemaVersion: Int
    var profiles: [VesselProfile]

    static func seeded() -> VesselProfileDocument {
        VesselProfileDocument(schemaVersion: currentSchemaVersion, profiles: BuiltInVesselID.seeds)
    }
}

enum VesselProfileStoreError: Error, Equatable {
    case missingProfile(UUID)
    case duplicateIdentifier(UUID)
    case invalidProfileData(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case readFailure(String)
    case writeFailure(String)
    case corruptedPersistenceData(String)
    case builtInProfileIsProtected(UUID)

    var message: String {
        switch self {
        case .missingProfile:
            return "That vessel is not in the library. The saved file was left unchanged."
        case .duplicateIdentifier:
            return "The library contains a repeated vessel identity. The saved file was left unchanged."
        case .invalidProfileData(let detail):
            return detail
        case .unsupportedSchemaVersion(let found, let supported):
            return "The vessel library uses schema \(found). This build reads schemas \(VesselProfileDocument.minimumReadableSchemaVersion) through \(supported). The saved file was left unchanged."
        case .readFailure(let detail):
            return "The vessel library could not be read. \(detail)"
        case .writeFailure(let detail):
            return "The vessel library could not be saved. \(detail)"
        case .corruptedPersistenceData:
            return "The vessel library is damaged and was left unchanged."
        case .builtInProfileIsProtected:
            return "Built-in vessels stay as seeded and cannot be edited or deleted."
        }
    }
}

protocol VesselProfileStoring: AnyObject {
    /// Nil means the store has never been written. A decode or read failure throws and must not be saved over.
    func loadDocument() throws -> VesselProfileDocument?
    func saveDocument(_ document: VesselProfileDocument) throws
}

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
