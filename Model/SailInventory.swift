import Foundation

enum SailCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case mainsail
    case headsail
    case symmetricSpinnaker
    case asymmetricSpinnaker
    case codeSail
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mainsail: return "Mainsail"
        case .headsail: return "Headsail"
        case .symmetricSpinnaker: return "Symmetric spinnaker"
        case .asymmetricSpinnaker: return "Asymmetric spinnaker"
        case .codeSail: return "Code sail"
        case .other: return "Other"
        }
    }

    var fitsMainsailSlot: Bool { self == .mainsail }
    var fitsHeadsailSlot: Bool { self == .headsail }
    var fitsDownwindSlot: Bool {
        switch self {
        case .symmetricSpinnaker, .asymmetricSpinnaker, .codeSail, .other:
            return true
        case .mainsail, .headsail:
            return false
        }
    }
}

enum SailSourceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case certificateListed
    case confirmedOnboard
    case userEntered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .certificateListed: return "Certificate listed"
        case .confirmedOnboard: return "Confirmed onboard"
        case .userEntered: return "User entered"
        }
    }
}

struct SailProvenance: Codable, Equatable, Sendable {
    var source: String
    var status: SailSourceStatus
}

struct MainsailMeasurements: Codable, Equatable, Sendable {
    var luffMeters: Double?
    var leechMeters: Double?
    var footMeters: Double?
    var areaSquareMeters: Double?
    /// Reefs the sail can take. Nil means unknown. The hoisted reef is on the active selection.
    var reefCount: Int?

    init(
        luffMeters: Double? = nil,
        leechMeters: Double? = nil,
        footMeters: Double? = nil,
        areaSquareMeters: Double? = nil,
        reefCount: Int? = nil
    ) {
        self.luffMeters = luffMeters
        self.leechMeters = leechMeters
        self.footMeters = footMeters
        self.areaSquareMeters = areaSquareMeters
        self.reefCount = reefCount
    }
}

struct HeadsailMeasurements: Codable, Equatable, Sendable {
    var luffMeters: Double?
    var leechMeters: Double?
    var footMeters: Double?
    var luffPerpendicularMeters: Double?
    var areaSquareMeters: Double?

    init(
        luffMeters: Double? = nil,
        leechMeters: Double? = nil,
        footMeters: Double? = nil,
        luffPerpendicularMeters: Double? = nil,
        areaSquareMeters: Double? = nil
    ) {
        self.luffMeters = luffMeters
        self.leechMeters = leechMeters
        self.footMeters = footMeters
        self.luffPerpendicularMeters = luffPerpendicularMeters
        self.areaSquareMeters = areaSquareMeters
    }
}

struct DownwindMeasurements: Codable, Equatable, Sendable {
    /// SLU, or the luff where the certificate uses one luff length.
    var luffMeters: Double?
    /// SLE.
    var leechMeters: Double?
    /// SF or SFL.
    var footMeters: Double?
    /// SHW.
    var halfWidthMeters: Double?
    var areaSquareMeters: Double?

    init(
        luffMeters: Double? = nil,
        leechMeters: Double? = nil,
        footMeters: Double? = nil,
        halfWidthMeters: Double? = nil,
        areaSquareMeters: Double? = nil
    ) {
        self.luffMeters = luffMeters
        self.leechMeters = leechMeters
        self.footMeters = footMeters
        self.halfWidthMeters = halfWidthMeters
        self.areaSquareMeters = areaSquareMeters
    }
}

struct GeneralSailMeasurements: Codable, Equatable, Sendable {
    var luffMeters: Double?
    var leechMeters: Double?
    var footMeters: Double?
    var areaSquareMeters: Double?

    init(
        luffMeters: Double? = nil,
        leechMeters: Double? = nil,
        footMeters: Double? = nil,
        areaSquareMeters: Double? = nil
    ) {
        self.luffMeters = luffMeters
        self.leechMeters = leechMeters
        self.footMeters = footMeters
        self.areaSquareMeters = areaSquareMeters
    }
}

struct SailRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var category: SailCategory
    var identification: String?
    var manufacturer: String?
    var model: String?
    var constructionYear: Int?
    var mainsail: MainsailMeasurements?
    var headsail: HeadsailMeasurements?
    var downwind: DownwindMeasurements?
    var general: GeneralSailMeasurements?
    var notes: String?
    var provenance: SailProvenance?

    init(
        id: UUID,
        name: String,
        category: SailCategory,
        identification: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        constructionYear: Int? = nil,
        mainsail: MainsailMeasurements? = nil,
        headsail: HeadsailMeasurements? = nil,
        downwind: DownwindMeasurements? = nil,
        general: GeneralSailMeasurements? = nil,
        notes: String? = nil,
        provenance: SailProvenance? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.identification = identification
        self.manufacturer = manufacturer
        self.model = model
        self.constructionYear = constructionYear
        self.mainsail = mainsail
        self.headsail = headsail
        self.downwind = downwind
        self.general = general
        self.notes = notes
        self.provenance = provenance
    }
}

/// Sails selected for use on one vessel. Empty slots are unselected.
struct ActiveSailSelection: Codable, Equatable, Sendable {
    var mainsailID: UUID?
    var headsailID: UUID?
    var downwindSailID: UUID?
    var mainsailReef: ReefStep = .full

    init(
        mainsailID: UUID? = nil,
        headsailID: UUID? = nil,
        downwindSailID: UUID? = nil,
        mainsailReef: ReefStep = .full
    ) {
        self.mainsailID = mainsailID
        self.headsailID = headsailID
        self.downwindSailID = downwindSailID
        self.mainsailReef = mainsailReef
    }

    /// Runtime hoisted-sail record. Identifiers are UUID strings. Reef state stays here.
    var runtimeConfiguration: SailConfiguration {
        SailConfiguration(
            mainSailID: mainsailID?.uuidString,
            headsailID: headsailID?.uuidString,
            downwindSailID: downwindSailID?.uuidString,
            mainsailReef: mainsailReef
        )
    }

    func clearingSails(absentFrom inventory: [SailRecord]) -> ActiveSailSelection {
        let ids = Set(inventory.map(\.id))
        var copy = self
        if let mainsailID, !ids.contains(mainsailID) { copy.mainsailID = nil }
        if let headsailID, !ids.contains(headsailID) { copy.headsailID = nil }
        if let downwindSailID, !ids.contains(downwindSailID) { copy.downwindSailID = nil }
        if copy.mainsailID == nil { copy.mainsailReef = .full }
        return copy
    }
}

enum ReferenceSailID {
    static let extasyMainsail = UUID(uuidString: "A1A10001-1390-4A07-8E35-4070F1A7E001")!
    static let extasyJib2 = UUID(uuidString: "A1A10002-1390-4A07-8E35-4070F1A7E001")!
    static let extasyHeadsail1 = UUID(uuidString: "A1A10003-1390-4A07-8E35-4070F1A7E001")!
    static let extasyAsymmetric = UUID(uuidString: "A1A10004-1390-4A07-8E35-4070F1A7E001")!
    static let nimanaMainsail = UUID(uuidString: "B1B10001-2015-4B46-9C12-46A0B1C2D003")!
    static let nimanaHeadsail = UUID(uuidString: "B1B10002-2015-4B46-9C12-46A0B1C2D003")!
    static let nimanaAsymmetric0 = UUID(uuidString: "B1B10003-2015-4B46-9C12-46A0B1C2D003")!
    static let nimanaAsymmetric11 = UUID(uuidString: "B1B10004-2015-4B46-9C12-46A0B1C2D003")!
    static let nimanaAsymmetricA0 = UUID(uuidString: "B1B10005-2015-4B46-9C12-46A0B1C2D003")!
}

enum ReferenceSails {
    static let extasyCertificate = "ORC Club Certificate 010a/26"
    static let nimanaCertificate = "ORC Club Certificate 009/26"

    static let extasy: [SailRecord] = [
        sail(
            id: ReferenceSailID.extasyMainsail,
            name: "Mainsail 1",
            category: .mainsail,
            identification: "1",
            mainsail: MainsailMeasurements(areaSquareMeters: 44.92),
            source: extasyCertificate
        ),
        sail(
            id: ReferenceSailID.extasyJib2,
            name: "Headsail jib2",
            category: .headsail,
            identification: "jib2",
            headsail: HeadsailMeasurements(luffMeters: 15.39, luffPerpendicularMeters: 4.55, areaSquareMeters: 36.64),
            source: extasyCertificate
        ),
        sail(
            id: ReferenceSailID.extasyHeadsail1,
            name: "Headsail 1",
            category: .headsail,
            identification: "1",
            headsail: HeadsailMeasurements(luffMeters: 14.80, luffPerpendicularMeters: 4.51, areaSquareMeters: 32.71),
            notes: "Measured 11/08/2017",
            source: extasyCertificate
        ),
        sail(
            id: ReferenceSailID.extasyAsymmetric,
            name: "Asymmetric 0",
            category: .asymmetricSpinnaker,
            identification: "0",
            downwind: DownwindMeasurements(luffMeters: 19.36, leechMeters: 15.17, footMeters: 9.97, halfWidthMeters: 10.05, areaSquareMeters: 144.36),
            notes: "Measured 08/03/2022",
            source: extasyCertificate
        )
    ]

    static let nimana: [SailRecord] = [
        sail(
            id: ReferenceSailID.nimanaMainsail,
            name: "Mainsail 0",
            category: .mainsail,
            identification: "0",
            mainsail: MainsailMeasurements(areaSquareMeters: 50.36),
            notes: "ODE17267-001. Measured 22/12/2025",
            source: nimanaCertificate
        ),
        sail(
            id: ReferenceSailID.nimanaHeadsail,
            name: "Headsail 0",
            category: .headsail,
            identification: "0",
            headsail: HeadsailMeasurements(luffMeters: 17.50, luffPerpendicularMeters: 5.97, areaSquareMeters: 53.26),
            notes: "ODE17267-002. Measured 08/12/2025",
            source: nimanaCertificate
        ),
        sail(
            id: ReferenceSailID.nimanaAsymmetric0,
            name: "Asymmetric 0",
            category: .asymmetricSpinnaker,
            identification: "0",
            downwind: DownwindMeasurements(luffMeters: 20.30, leechMeters: 17.30, footMeters: 9.72, halfWidthMeters: 10.55, areaSquareMeters: 162.68),
            notes: "ODE17267-003. Measured 24/01/2026",
            source: nimanaCertificate
        ),
        sail(
            id: ReferenceSailID.nimanaAsymmetric11,
            name: "Asymmetric 11",
            category: .asymmetricSpinnaker,
            identification: "11",
            downwind: DownwindMeasurements(luffMeters: 19.51, leechMeters: 17.14, footMeters: 9.56, halfWidthMeters: 10.57, areaSquareMeters: 158.33),
            notes: "Measured 2023",
            source: nimanaCertificate
        ),
        sail(
            id: ReferenceSailID.nimanaAsymmetricA0,
            name: "Asymmetric A0",
            category: .asymmetricSpinnaker,
            identification: "A0",
            downwind: DownwindMeasurements(luffMeters: 18.20, leechMeters: 16.70, footMeters: 10.07, halfWidthMeters: 7.56, areaSquareMeters: 117.23),
            notes: "Measured 2023",
            source: nimanaCertificate
        )
    ]

    private static func sail(
        id: UUID,
        name: String,
        category: SailCategory,
        identification: String,
        mainsail: MainsailMeasurements? = nil,
        headsail: HeadsailMeasurements? = nil,
        downwind: DownwindMeasurements? = nil,
        notes: String? = nil,
        source: String
    ) -> SailRecord {
        SailRecord(
            id: id,
            name: name,
            category: category,
            identification: identification,
            mainsail: mainsail,
            headsail: headsail,
            downwind: downwind,
            notes: notes,
            provenance: SailProvenance(source: source, status: .certificateListed)
        )
    }
}
