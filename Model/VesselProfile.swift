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
    case none
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
