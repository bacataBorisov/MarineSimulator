import SwiftUI

struct SailDraft: Identifiable, Equatable {
    var id: UUID
    var name = ""
    var category: SailCategory = .mainsail
    var identification = ""
    var manufacturer = ""
    var model = ""
    var yearText = ""
    var notes = ""
    var provenanceSource = ""
    var provenanceStatus: SailSourceStatus?
    var luff = ""
    var leech = ""
    var foot = ""
    var area = ""
    var lp = ""
    var halfWidth = ""
    var reefCountText = ""

    init(id: UUID, name: String = "", category: SailCategory = .mainsail) {
        self.id = id
        self.name = name
        self.category = category
    }

    init(record: SailRecord) {
        id = record.id
        name = record.name
        category = record.category
        identification = record.identification ?? ""
        manufacturer = record.manufacturer ?? ""
        model = record.model ?? ""
        yearText = record.constructionYear.map(String.init) ?? ""
        notes = record.notes ?? ""
        provenanceSource = record.provenance?.source ?? ""
        provenanceStatus = record.provenance?.status
        switch record.category {
        case .mainsail:
            luff = Self.display(record.mainsail?.luffMeters)
            leech = Self.display(record.mainsail?.leechMeters)
            foot = Self.display(record.mainsail?.footMeters)
            area = Self.display(record.mainsail?.areaSquareMeters)
            reefCountText = record.mainsail?.reefCount.map(String.init) ?? ""
        case .headsail:
            luff = Self.display(record.headsail?.luffMeters)
            leech = Self.display(record.headsail?.leechMeters)
            foot = Self.display(record.headsail?.footMeters)
            lp = Self.display(record.headsail?.luffPerpendicularMeters)
            area = Self.display(record.headsail?.areaSquareMeters)
        case .symmetricSpinnaker, .asymmetricSpinnaker:
            luff = Self.display(record.downwind?.luffMeters)
            leech = Self.display(record.downwind?.leechMeters)
            foot = Self.display(record.downwind?.footMeters)
            halfWidth = Self.display(record.downwind?.halfWidthMeters)
            area = Self.display(record.downwind?.areaSquareMeters)
        case .codeSail, .other:
            luff = Self.display(record.general?.luffMeters)
            leech = Self.display(record.general?.leechMeters)
            foot = Self.display(record.general?.footMeters)
            area = Self.display(record.general?.areaSquareMeters)
        }
    }

    var signature: Signature {
        Signature(
            id: id,
            name: trimmed(name),
            category: category,
            identification: trimmed(identification),
            manufacturer: trimmed(manufacturer),
            model: trimmed(model),
            year: trimmed(yearText),
            notes: trimmed(notes),
            provenanceSource: trimmed(provenanceSource),
            provenanceStatus: provenanceStatus,
            luff: Self.token(luff),
            leech: Self.token(leech),
            foot: Self.token(foot),
            area: Self.token(area),
            lp: Self.token(lp),
            halfWidth: Self.token(halfWidth),
            reef: trimmed(reefCountText)
        )
    }

    func record() throws -> SailRecord {
        let trimmedName = trimmed(name)
        guard !trimmedName.isEmpty else {
            throw VesselProfileStoreError.invalidProfileData("A sail name is required.")
        }
        let year = try Self.year(yearText)
        let reefCount = try Self.reefCount(reefCountText)
        var record = SailRecord(id: id, name: trimmedName, category: category, constructionYear: year)
        record.identification = trimmed(identification).nilIfEmpty
        record.manufacturer = trimmed(manufacturer).nilIfEmpty
        record.model = trimmed(model).nilIfEmpty
        record.notes = trimmed(notes).nilIfEmpty
        let source = trimmed(provenanceSource)
        if let provenanceStatus {
            record.provenance = SailProvenance(source: source.isEmpty ? "User" : source, status: provenanceStatus)
        } else if !source.isEmpty {
            record.provenance = SailProvenance(source: source, status: .userEntered)
        }
        switch category {
        case .mainsail:
            record.mainsail = MainsailMeasurements(
                luffMeters: try length(luff, "Sail luff"),
                leechMeters: try length(leech, "Sail leech"),
                footMeters: try length(foot, "Sail foot"),
                areaSquareMeters: try length(area, "Sail area"),
                reefCount: reefCount
            )
        case .headsail:
            record.headsail = HeadsailMeasurements(
                luffMeters: try length(luff, "Sail luff"),
                leechMeters: try length(leech, "Sail leech"),
                footMeters: try length(foot, "Sail foot"),
                luffPerpendicularMeters: try length(lp, "LP"),
                areaSquareMeters: try length(area, "Sail area")
            )
        case .symmetricSpinnaker, .asymmetricSpinnaker:
            record.downwind = DownwindMeasurements(
                luffMeters: try length(luff, "SLU"),
                leechMeters: try length(leech, "SLE"),
                footMeters: try length(foot, "SF"),
                halfWidthMeters: try length(halfWidth, "SHW"),
                areaSquareMeters: try length(area, "Sail area")
            )
        case .codeSail, .other:
            record.general = GeneralSailMeasurements(
                luffMeters: try length(luff, "Sail luff"),
                leechMeters: try length(leech, "Sail leech"),
                footMeters: try length(foot, "Sail foot"),
                areaSquareMeters: try length(area, "Sail area")
            )
        }
        return record
    }

    struct Signature: Equatable {
        var id: UUID
        var name: String
        var category: SailCategory
        var identification: String
        var manufacturer: String
        var model: String
        var year: String
        var notes: String
        var provenanceSource: String
        var provenanceStatus: SailSourceStatus?
        var luff: Token
        var leech: Token
        var foot: Token
        var area: Token
        var lp: Token
        var halfWidth: Token
        var reef: String
    }

    enum Token: Equatable {
        case empty
        case value(Double)
        case invalid(String)
    }

    private func length(_ text: String, _ label: String) throws -> Double? {
        switch Self.token(text) {
        case .empty:
            return nil
        case .invalid:
            throw VesselProfileStoreError.invalidProfileData("\(label) must be a number.")
        case .value(let value):
            guard value > 0 else {
                throw VesselProfileStoreError.invalidProfileData("\(label) must be greater than zero.")
            }
            return value
        }
    }

    private static func year(_ text: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let year = Int(trimmed) else {
            throw VesselProfileStoreError.invalidProfileData("Sail construction year must be a whole number.")
        }
        guard (1800...2100).contains(year) else {
            throw VesselProfileStoreError.invalidProfileData("Sail construction year must be from 1800 through 2100.")
        }
        return year
    }

    private static func reefCount(_ text: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let count = Int(trimmed), (0...3).contains(count) else {
            throw VesselProfileStoreError.invalidProfileData("Reef count must be from 0 through 3.")
        }
        return count
    }

    private static func display(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    private static func token(_ text: String) -> Token {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let value = parse(trimmed), value.isFinite else { return .invalid(trimmed) }
        return .value((value * 1_000_000).rounded() / 1_000_000)
    }

    private static func parse(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.number(from: text)?.doubleValue
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct SailInventorySection: View {
    var profile: VesselProfile
    @Bindable var session: VesselLibrarySession
    var simulator: NMEASimulator

    var body: some View {
        Section("Sail inventory") {
            if session.buffer.sails.isEmpty {
                Text("No sails recorded.")
                    .foregroundStyle(.secondary)
            }
            ForEach(session.buffer.sails) { sail in
                Button {
                    session.editingSailID = sail.id
                } label: {
                    HStack {
                        Image(systemName: session.editingSailID == sail.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.secondary)
                        Text(sail.name.isEmpty ? "Unnamed sail" : sail.name)
                        Spacer()
                        Text(sail.category.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sail.name), \(sail.category.title)")
            }
            HStack {
                Button("Add Sail") { addSail() }
                Button("Duplicate Sail") { duplicateSail() }
                    .disabled(selectedIndex == nil)
                Button("Delete Sail") { deleteSail() }
                    .disabled(selectedIndex == nil)
            }
            if let selectedIndex {
                SailDraftFields(draft: $session.buffer.sails[selectedIndex])
            }
            Text("Inventory for \(profile.name). Blank measurements stay unknown. A failed save keeps the typed values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedIndex: Int? {
        guard let editingSailID = session.editingSailID else { return nil }
        return session.buffer.sails.firstIndex { $0.id == editingSailID }
    }

    private func addSail() {
        let draft = SailDraft(id: UUID(), name: "New sail", category: .mainsail)
        session.buffer.sails.append(draft)
        session.editingSailID = draft.id
    }

    private func duplicateSail() {
        guard let selectedIndex else { return }
        var copy = session.buffer.sails[selectedIndex]
        copy.id = UUID()
        copy.name = "\(copy.name) Copy"
        session.buffer.sails.append(copy)
        session.editingSailID = copy.id
    }

    private func deleteSail() {
        guard let selectedIndex else { return }
        session.buffer.sails.remove(at: selectedIndex)
        session.editingSailID = session.buffer.sails.first?.id
    }
}

private struct SailDraftFields: View {
    @Binding var draft: SailDraft

    var body: some View {
        TextField("Name", text: $draft.name)
        Picker("Category", selection: $draft.category) {
            ForEach(SailCategory.allCases) { category in
                Text(category.title).tag(category)
            }
        }
        TextField("Identification", text: $draft.identification)
        TextField("Manufacturer", text: $draft.manufacturer)
        TextField("Model", text: $draft.model)
        TextField("Construction year", text: $draft.yearText)
        measurementFields
        TextField("Notes", text: $draft.notes)
        TextField("Source", text: $draft.provenanceSource)
        Picker("Source status", selection: $draft.provenanceStatus) {
            Text("Not recorded").tag(SailSourceStatus?.none)
            ForEach(SailSourceStatus.allCases) { status in
                Text(status.title).tag(Optional(status))
            }
        }
    }

    @ViewBuilder
    private var measurementFields: some View {
        switch draft.category {
        case .mainsail:
            measure("Luff", text: $draft.luff, unit: "m")
            measure("Leech", text: $draft.leech, unit: "m")
            measure("Foot", text: $draft.foot, unit: "m")
            measure("Area", text: $draft.area, unit: "m²")
            TextField("Reefs available", text: $draft.reefCountText)
        case .headsail:
            measure("Luff", text: $draft.luff, unit: "m")
            measure("Leech", text: $draft.leech, unit: "m")
            measure("Foot", text: $draft.foot, unit: "m")
            measure("LP", text: $draft.lp, unit: "m")
            measure("Area", text: $draft.area, unit: "m²")
        case .symmetricSpinnaker, .asymmetricSpinnaker:
            measure("SLU", text: $draft.luff, unit: "m")
            measure("SLE", text: $draft.leech, unit: "m")
            measure("SF", text: $draft.foot, unit: "m")
            measure("SHW", text: $draft.halfWidth, unit: "m")
            measure("Area", text: $draft.area, unit: "m²")
        case .codeSail, .other:
            measure("Luff", text: $draft.luff, unit: "m")
            measure("Leech", text: $draft.leech, unit: "m")
            measure("Foot", text: $draft.foot, unit: "m")
            measure("Area", text: $draft.area, unit: "m²")
        }
    }

    private func measure(_ title: String, text: Binding<String>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ActiveSailControls: View {
    enum Target {
        case savedSelection
        case hoisted
    }

    var profile: VesselProfile
    var target: Target
    @Bindable var simulator: NMEASimulator
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(target == .hoisted ? "Hoisted sails" : "Saved sail selection")
                .font(.headline)
            slotPicker("Mainsail", selection: slot(\.mainsailID), sails: profile.inventory.filter(\.category.fitsMainsailSlot))
            Picker("Reef", selection: reefBinding) {
                Text("Full").tag(ReefStep.full)
                Text("Reef 1").tag(ReefStep.reef1)
                Text("Reef 2").tag(ReefStep.reef2)
                Text("Reef 3").tag(ReefStep.reef3)
            }
            .disabled(displayedSelection.mainsailID == nil)
            slotPicker("Headsail", selection: slot(\.headsailID), sails: profile.inventory.filter(\.category.fitsHeadsailSlot))
            slotPicker("Downwind", selection: slot(\.downwindSailID), sails: profile.inventory.filter(\.category.fitsDownwindSlot))
            Text(target == .hoisted
                 ? "This changes the sails hoisted for the current session. The saved selection stays unchanged."
                 : "This is the selection adopted when the vessel becomes active. None leaves a slot empty.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(target == .hoisted ? "Hoisted sails for \(profile.name)" : "Saved sails for \(profile.name)")
    }

    private var displayedSelection: ActiveSailSelection {
        switch target {
        case .savedSelection:
            return profile.activeSails
        case .hoisted:
            return ActiveSailSelection(
                mainsailID: simulator.sailConfiguration.mainSailID.flatMap(UUID.init(uuidString:)),
                headsailID: simulator.sailConfiguration.headsailID.flatMap(UUID.init(uuidString:)),
                downwindSailID: simulator.sailConfiguration.downwindSailID.flatMap(UUID.init(uuidString:)),
                mainsailReef: simulator.sailConfiguration.mainsailReef
            )
        }
    }

    private func slotPicker(_ title: String, selection: Binding<UUID?>, sails: [SailRecord]) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(UUID?.none)
            ForEach(sails) { sail in
                Text("\(sail.name) · \(sail.category.title)").tag(Optional(sail.id))
            }
        }
    }

    private func slot(_ keyPath: WritableKeyPath<ActiveSailSelection, UUID?>) -> Binding<UUID?> {
        Binding(
            get: { displayedSelection[keyPath: keyPath] },
            set: { newValue in
                var selection = displayedSelection
                selection[keyPath: keyPath] = newValue
                if selection.mainsailID == nil {
                    selection.mainsailReef = .full
                }
                apply(selection)
            }
        )
    }

    private var reefBinding: Binding<ReefStep> {
        Binding(
            get: { displayedSelection.mainsailReef },
            set: { newValue in
                var selection = displayedSelection
                selection.mainsailReef = newValue
                apply(selection)
            }
        )
    }

    private func apply(_ selection: ActiveSailSelection) {
        do {
            switch target {
            case .savedSelection:
                try simulator.replaceActiveSails(profile.id, with: selection)
            case .hoisted:
                try simulator.setHoistedSails(selection)
            }
            message = nil
        } catch let error as VesselProfileStoreError {
            message = error.message
        } catch {
            message = error.localizedDescription
        }
    }
}
