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

    /// Category picker write. The inventory rows are `SailEditorSchema.inventoryFields(for:)` of this value.
    mutating func selectCategory(_ category: SailCategory) {
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
        if VesselEditBuffer.isIncompleteDecimal(trimmed) { return .invalid(trimmed) }
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

enum SailEditorControl: Equatable {
    case text
    case menu
    case measurement(unit: String)
    case reefCount

    /// Unit rendered beside the value. Nil means the row has no unit.
    var adjacentUnit: String? {
        if case .measurement(let unit) = self { return unit }
        return nil
    }
}

/// Slot and reef writes used by the active-sail menus.
enum ActiveSailSelectionEdit {
    static func assignSlot(
        _ selection: inout ActiveSailSelection,
        _ keyPath: WritableKeyPath<ActiveSailSelection, UUID?>,
        to newValue: UUID?
    ) {
        selection[keyPath: keyPath] = newValue
        if selection.mainsailID == nil {
            selection.mainsailReef = .full
        }
    }

    static func assignReef(_ selection: inout ActiveSailSelection, to step: ReefStep) {
        selection.mainsailReef = step
    }

    static func reefPickerIsEnabled(_ selection: ActiveSailSelection) -> Bool {
        selection.mainsailID != nil
    }
}

struct SailEditorField: Equatable, Identifiable {
    enum ID: String, Equatable {
        case name
        case category
        case identification
        case manufacturer
        case model
        case year
        case notes
        case source
        case sourceStatus
        case luff
        case leech
        case foot
        case area
        case lp
        case halfWidth
        case reefCount
    }

    var id: ID
    var title: String
    var control: SailEditorControl
    var accessibilityLabel: String
}

struct ActiveSailEditorField: Equatable, Identifiable {
    enum ID: String, Equatable {
        case mainsail
        case reef
        case headsail
        case downwind
    }

    var id: ID
    var title: String
    var control: SailEditorControl
    var accessibilityLabel: String
}

/// Labels and controls for the sail editor. The inventory and active-sail views render this list.
enum SailEditorSchema {
    static func inventoryFields(for category: SailCategory) -> [SailEditorField] {
        identityFields + measurements(for: category) + provenanceFields
    }

    static func activeSelectionFields() -> [ActiveSailEditorField] {
        [
            active(.mainsail, "Mainsail", .menu),
            active(.reef, "Reef", .menu),
            active(.headsail, "Headsail", .menu),
            active(.downwind, "Downwind", .menu),
        ]
    }

    private static var identityFields: [SailEditorField] {
        [
            field(.name, "Name", .text),
            field(.category, "Category", .menu),
            field(.identification, "Identification", .text),
            field(.manufacturer, "Manufacturer", .text),
            field(.model, "Model", .text),
            field(.year, "Construction year", .text),
        ]
    }

    private static var provenanceFields: [SailEditorField] {
        [
            field(.notes, "Notes", .text),
            field(.source, "Source", .text),
            field(.sourceStatus, "Source status", .menu),
        ]
    }

    private static func measurements(for category: SailCategory) -> [SailEditorField] {
        switch category {
        case .mainsail:
            return [
                measure(.luff, "Luff"),
                measure(.leech, "Leech"),
                measure(.foot, "Foot"),
                measure(.area, "Area", unit: "m²"),
                field(.reefCount, "Reefs available", .reefCount),
            ]
        case .headsail:
            return [
                measure(.luff, "Luff"),
                measure(.leech, "Leech"),
                measure(.foot, "Foot"),
                measure(.lp, "LP"),
                measure(.area, "Area", unit: "m²"),
            ]
        case .symmetricSpinnaker, .asymmetricSpinnaker:
            return [
                measure(.luff, "SLU"),
                measure(.leech, "SLE"),
                measure(.foot, "SF"),
                measure(.halfWidth, "SHW"),
                measure(.area, "Area", unit: "m²"),
            ]
        case .codeSail, .other:
            return [
                measure(.luff, "Luff"),
                measure(.leech, "Leech"),
                measure(.foot, "Foot"),
                measure(.area, "Area", unit: "m²"),
            ]
        }
    }

    private static func field(_ id: SailEditorField.ID, _ title: String, _ control: SailEditorControl) -> SailEditorField {
        SailEditorField(
            id: id,
            title: title,
            control: control,
            accessibilityLabel: FormRowAccessibility.editorLabel(title)
        )
    }

    private static func measure(_ id: SailEditorField.ID, _ title: String, unit: String = "m") -> SailEditorField {
        field(id, title, .measurement(unit: unit))
    }

    private static func active(_ id: ActiveSailEditorField.ID, _ title: String, _ control: SailEditorControl) -> ActiveSailEditorField {
        ActiveSailEditorField(
            id: id,
            title: title,
            control: control,
            accessibilityLabel: FormRowAccessibility.editorLabel(title)
        )
    }
}

struct SailInventorySection: View {
    var profile: VesselProfile
    @Bindable var session: VesselLibrarySession
    var simulator: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
            if session.buffer.sails.isEmpty {
                Text("No sails recorded.")
                    .foregroundStyle(DesignToken.Status.neutral)
            }
            ForEach(session.buffer.sails) { sail in
                let isSelected = session.editingSailID == sail.id
                Button {
                    session.editingSailID = sail.id
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? DesignToken.Status.success : DesignToken.Status.neutral)
                        Text(sail.name.isEmpty ? "Unnamed sail" : sail.name)
                        Spacer()
                        Text(sail.category.title)
                            .foregroundStyle(DesignToken.Status.neutral)
                    }
                    .padding(.horizontal, DesignToken.Spacing.stacked)
                    .padding(.vertical, DesignToken.Spacing.stacked)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: DesignToken.Radius.compactCard, style: .continuous)
                                .fill(DesignToken.Surface.selection)
                        }
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
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("Vessel inventory summary")
                .accessibilityLabel("Inventory for \(profile.name)")
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

struct SailDraftFields: View {
    @Binding var draft: SailDraft

    var body: some View {
        ForEach(SailEditorSchema.inventoryFields(for: draft.category)) { field in
            editor(field)
        }
    }

    @ViewBuilder
    private func editor(_ field: SailEditorField) -> some View {
        switch field.id {
        case .name:
            text(field, text: $draft.name) { raw in
                raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A sail name is required." : nil
            }
        case .category:
            FormMenuRow(title: field.title, accessibilityLabel: field.accessibilityLabel, selection: categorySelection) {
                ForEach(SailCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
        case .identification:
            text(field, text: $draft.identification)
        case .manufacturer:
            text(field, text: $draft.manufacturer)
        case .model:
            text(field, text: $draft.model)
        case .year:
            text(field, text: $draft.yearText, inputMode: .wholeNumber) { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                guard let year = Int(trimmed) else { return "Sail construction year must be a whole number." }
                return (1800...2100).contains(year) ? nil : "Sail construction year must be from 1800 through 2100."
            }
        case .notes:
            text(field, text: $draft.notes)
        case .source:
            text(field, text: $draft.provenanceSource)
        case .sourceStatus:
            FormMenuRow(title: field.title, accessibilityLabel: field.accessibilityLabel, selection: $draft.provenanceStatus) {
                Text("Not recorded").tag(SailSourceStatus?.none)
                ForEach(SailSourceStatus.allCases) { status in
                    Text(status.title).tag(Optional(status))
                }
            }
        case .luff:
            measurement(field, text: $draft.luff)
        case .leech:
            measurement(field, text: $draft.leech)
        case .foot:
            measurement(field, text: $draft.foot)
        case .area:
            measurement(field, text: $draft.area)
        case .lp:
            measurement(field, text: $draft.lp)
        case .halfWidth:
            measurement(field, text: $draft.halfWidth)
        case .reefCount:
            text(field, text: $draft.reefCountText, inputMode: .wholeNumber) { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                guard let count = Int(trimmed), (0...3).contains(count) else {
                    return "Reef count must be from 0 through 3."
                }
                return nil
            }
        }
    }

    private func text(
        _ field: SailEditorField,
        text: Binding<String>,
        inputMode: FormTextInputMode = .plain,
        validationError: ((String) -> String?)? = nil
    ) -> some View {
        FormTextRow(
            title: field.title,
            text: text,
            accessibilityLabel: field.accessibilityLabel,
            inputMode: inputMode,
            validationError: validationError
        )
    }

    private var categorySelection: Binding<SailCategory> {
        Binding(
            get: { draft.category },
            set: { draft.selectCategory($0) }
        )
    }

    private func measurement(_ field: SailEditorField, text: Binding<String>) -> some View {
        FormTextRow(
            title: field.title,
            text: text,
            accessibilityLabel: field.accessibilityLabel,
            unit: field.control.adjacentUnit,
            inputMode: .decimal
        ) { raw in
            switch VesselEditBuffer.token(raw) {
            case .empty:
                return nil
            case .invalid:
                return "\(field.title) must be a positive number."
            case .value(let value):
                return value > 0 ? nil : "\(field.title) must be greater than zero."
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
    var compactRail: Bool = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
            Text(target == .hoisted ? "Hoisted sails" : "Saved sail selection")
                .font(DesignToken.Typography.section)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h2)
            ForEach(SailEditorSchema.activeSelectionFields()) { field in
                activeRow(field)
            }
            Text(target == .hoisted
                 ? "This changes the sails hoisted for the current session. The saved selection stays unchanged."
                 : "This is the selection adopted when the vessel becomes active. None leaves a slot empty.")
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)
            if let message {
                Text(message)
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.error)
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

    @ViewBuilder
    private func activeRow(_ field: ActiveSailEditorField) -> some View {
        switch field.id {
        case .mainsail:
            slotMenu(field, selection: slot(\.mainsailID), sails: profile.inventory.filter(\.category.fitsMainsailSlot))
        case .reef:
            if compactRail {
                compactRailMenu(
                    field,
                    selection: reefBinding,
                    isEnabled: ActiveSailSelectionEdit.reefPickerIsEnabled(displayedSelection)
                ) {
                    Text("Full").tag(ReefStep.full)
                    Text("Reef 1").tag(ReefStep.reef1)
                    Text("Reef 2").tag(ReefStep.reef2)
                    Text("Reef 3").tag(ReefStep.reef3)
                }
            } else {
                FormMenuRow(
                    title: field.title,
                    accessibilityLabel: field.accessibilityLabel,
                    selection: reefBinding,
                    isEnabled: ActiveSailSelectionEdit.reefPickerIsEnabled(displayedSelection)
                ) {
                    Text("Full").tag(ReefStep.full)
                    Text("Reef 1").tag(ReefStep.reef1)
                    Text("Reef 2").tag(ReefStep.reef2)
                    Text("Reef 3").tag(ReefStep.reef3)
                }
            }
        case .headsail:
            slotMenu(field, selection: slot(\.headsailID), sails: profile.inventory.filter(\.category.fitsHeadsailSlot))
        case .downwind:
            slotMenu(field, selection: slot(\.downwindSailID), sails: profile.inventory.filter(\.category.fitsDownwindSlot))
        }
    }

    @ViewBuilder
    private func slotMenu(_ field: ActiveSailEditorField, selection: Binding<UUID?>, sails: [SailRecord]) -> some View {
        if compactRail {
            compactRailMenu(field, selection: selection) {
                Text("None").tag(UUID?.none)
                ForEach(sails) { sail in
                    Text("\(sail.name) · \(sail.category.title)").tag(Optional(sail.id))
                }
            }
        } else {
            FormMenuRow(title: field.title, accessibilityLabel: field.accessibilityLabel, selection: selection) {
                Text("None").tag(UUID?.none)
                ForEach(sails) { sail in
                    Text("\(sail.name) · \(sail.category.title)").tag(Optional(sail.id))
                }
            }
        }
    }

    private func compactRailMenu<Selection: Hashable, Content: View>(
        _ field: ActiveSailEditorField,
        selection: Binding<Selection>,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.row) {
            Text(field.title)
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(.secondary)
            Spacer(minLength: DesignToken.Spacing.related)
            Picker(field.accessibilityLabel, selection: selection, content: content)
                .labelsHidden()
                .accessibilityLabel(field.accessibilityLabel)
                .accessibilityIdentifier(field.accessibilityLabel)
                .pickerStyle(.menu)
                .disabled(!isEnabled)
                .frame(width: 152, alignment: .trailing)
        }
    }

    private func slot(_ keyPath: WritableKeyPath<ActiveSailSelection, UUID?>) -> Binding<UUID?> {
        Binding(
            get: { displayedSelection[keyPath: keyPath] },
            set: { newValue in
                var selection = displayedSelection
                ActiveSailSelectionEdit.assignSlot(&selection, keyPath, to: newValue)
                apply(selection)
            }
        )
    }

    private var reefBinding: Binding<ReefStep> {
        Binding(
            get: { displayedSelection.mainsailReef },
            set: { newValue in
                var selection = displayedSelection
                ActiveSailSelectionEdit.assignReef(&selection, to: newValue)
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
