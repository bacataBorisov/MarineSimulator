import SwiftUI

/// Setup inspection state. Highlighting a row does not change the active simulation vessel.
@Observable
final class VesselLibrarySession {
    var highlightedID: UUID?
    var editingSailID: UUID?
    var buffer = VesselEditBuffer()
    var isConfirmingUnsavedChanges = false
    private(set) var lastResult: VesselLibraryResult = .idle
    private var pendingLeave: VesselLeaveIntent?

    enum VesselLibraryResult: Equatable {
        case idle
        case succeeded
        case failed(VesselProfileStoreError)
    }

    var lastChangeSucceeded: Bool {
        if case .succeeded = lastResult { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let error) = lastResult { return error.message }
        return nil
    }

    func hasUnsavedChanges(in simulator: NMEASimulator) -> Bool {
        guard let profile = highlightedProfile(in: simulator) else { return false }
        let stored = VesselEditBuffer(profile: profile)
        if profile.origin == .builtIn {
            return buffer.sailSignature != stored.sailSignature
        }
        return buffer.signature != stored.signature
    }

    func show(_ id: UUID, on simulator: NMEASimulator) {
        highlightedID = id
        if let profile = highlightedProfile(in: simulator) {
            buffer = VesselEditBuffer(profile: profile)
            if editingSailID == nil || !buffer.sails.contains(where: { $0.id == editingSailID }) {
                editingSailID = buffer.sails.first?.id
            }
        }
    }

    func highlight(_ id: UUID) {
        highlightedID = id
    }

    func requestLeave(_ intent: VesselLeaveIntent, on simulator: NMEASimulator) -> VesselLeaveGate {
        if case .highlight(let id) = intent, id == highlightedID { return .allowed }
        if case .activate(let id) = intent, id == highlightedID { return .allowed }
        guard hasUnsavedChanges(in: simulator) else {
            reveal(intent, on: simulator)
            return .allowed
        }
        pendingLeave = intent
        isConfirmingUnsavedChanges = true
        return .needsConfirmation
    }

    func resolveUnsavedChanges(_ choice: UnsavedEditChoice, on simulator: NMEASimulator) -> UnsavedResolution {
        let intent = pendingLeave
        pendingLeave = nil
        isConfirmingUnsavedChanges = false
        switch choice {
        case .cancel:
            return .stayed
        case .discard:
            restoreBuffer(from: simulator)
            if let intent {
                reveal(intent, on: simulator)
                return .perform(intent)
            }
            return .stayed
        case .save:
            guard saveBuffer(on: simulator) else { return .stayed }
            if let intent {
                reveal(intent, on: simulator)
                return .perform(intent)
            }
            return .stayed
        }
    }

    @discardableResult
    func saveBuffer(on simulator: NMEASimulator) -> Bool {
        guard let profile = highlightedProfile(in: simulator) else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return false
        }
        let metadata: VesselEditableMetadata?
        if profile.origin == .custom {
            let trimmed = buffer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                lastResult = .failed(.invalidProfileData("A vessel name is required."))
                return false
            }
            guard case .value(let year) = buffer.parsedYear else {
                lastResult = .failed(.invalidProfileData("Construction year must be a whole number."))
                return false
            }
            if let year, !(1800...2100).contains(year) {
                lastResult = .failed(.invalidProfileData("Construction year must be from 1800 through 2100."))
                return false
            }
            switch buffer.editableMetadata(name: trimmed, year: year) {
            case .success(let value):
                metadata = value
            case .failure(let error):
                lastResult = .failed(error)
                return false
            }
        } else {
            metadata = nil
        }
        switch buffer.sailRecords() {
        case .success(let sails):
            let saved = perform(on: simulator) {
                try simulator.saveProfileEdits(profile.id, metadata: metadata, inventory: sails)
                return true
            } != nil
            if saved, let stored = highlightedProfile(in: simulator) {
                buffer = VesselEditBuffer(profile: stored)
            }
            return saved
        case .failure(let error):
            lastResult = .failed(error)
            return false
        }
    }

    @discardableResult
    func createVessel(
        name: String,
        modelName: String?,
        constructionYear: Int?,
        on simulator: NMEASimulator
    ) -> VesselProfile? {
        perform(on: simulator) {
            let profile = try simulator.createCustomVessel(
                name: name,
                modelName: modelName,
                constructionYear: constructionYear
            )
            highlightedID = profile.id
            return profile
        }
    }

    @discardableResult
    func saveMetadata(id: UUID, metadata: VesselEditableMetadata, on simulator: NMEASimulator) -> Bool {
        perform(on: simulator) {
            try simulator.updateCustomVessel(id, metadata: metadata)
            return true
        } != nil
    }

    @discardableResult
    func saveMetadata(
        id: UUID,
        name: String,
        modelName: String?,
        constructionYear: Int?,
        on simulator: NMEASimulator
    ) -> Bool {
        perform(on: simulator) {
            try simulator.updateCustomVessel(id, name: name, modelName: modelName, constructionYear: constructionYear)
            return true
        } != nil
    }

    @discardableResult
    func duplicateHighlighted(on simulator: NMEASimulator) -> VesselProfile? {
        guard let highlightedID else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return nil
        }
        return perform(on: simulator) {
            let copy = try simulator.duplicateVessel(highlightedID)
            self.highlightedID = copy.id
            return copy
        }
    }

    @discardableResult
    func deleteHighlighted(on simulator: NMEASimulator) -> Bool {
        guard let highlightedID else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return false
        }
        let deleted = perform(on: simulator) {
            try simulator.deleteCustomVessel(highlightedID)
            return true
        } != nil
        if deleted {
            self.highlightedID = nil
        }
        return deleted
    }

    func activateHighlighted(on simulator: NMEASimulator) {
        guard let highlightedID else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return
        }
        guard simulator.vesselStoreError == nil else {
            lastResult = .failed(simulator.vesselStoreError ?? .readFailure("The vessel library is not available."))
            return
        }
        guard simulator.vessels.contains(where: { $0.id == highlightedID }) else {
            lastResult = .failed(.missingProfile(highlightedID))
            return
        }
        simulator.selectVessel(highlightedID)
        if simulator.selectedVesselID == highlightedID {
            lastResult = .succeeded
        } else {
            lastResult = .failed(.writeFailure("The active vessel was not changed."))
        }
    }

    @discardableResult
    private func perform<T>(on simulator: NMEASimulator, _ body: () throws -> T) -> T? {
        if let vesselStoreError = simulator.vesselStoreError {
            lastResult = .failed(vesselStoreError)
            return nil
        }
        do {
            let value = try body()
            lastResult = .succeeded
            return value
        } catch let error as VesselProfileStoreError {
            lastResult = .failed(error)
            return nil
        } catch {
            lastResult = .failed(.writeFailure(error.localizedDescription))
            return nil
        }
    }

    private func highlightedProfile(in simulator: NMEASimulator) -> VesselProfile? {
        guard let highlightedID else { return nil }
        return simulator.vessels.first { $0.id == highlightedID }
    }

    private func restoreBuffer(from simulator: NMEASimulator) {
        if let profile = highlightedProfile(in: simulator) {
            buffer = VesselEditBuffer(profile: profile)
            if editingSailID == nil || !buffer.sails.contains(where: { $0.id == editingSailID }) {
                editingSailID = buffer.sails.first?.id
            }
        }
    }

    private func reveal(_ intent: VesselLeaveIntent, on simulator: NMEASimulator) {
        switch intent {
        case .highlight(let id), .activate(let id), .duplicate(let id), .delete(let id), .rename(let id):
            if highlightedID != id {
                show(id, on: simulator)
            }
        case .create:
            break
        }
    }
}

enum VesselLeaveIntent: Equatable {
    case highlight(UUID)
    case create
    case duplicate(UUID)
    case delete(UUID)
    case rename(UUID)
    case activate(UUID)
}

enum VesselLeaveGate: Equatable {
    case allowed
    case needsConfirmation
}

enum UnsavedEditChoice: Equatable {
    case save
    case discard
    case cancel
}

enum UnsavedResolution: Equatable {
    case stayed
    case perform(VesselLeaveIntent)
}

struct VesselEditBuffer: Equatable {
    var name = ""
    var manufacturer = ""
    var modelName = ""
    var yearText = ""
    var sailNumber = ""
    var registration = ""
    var lengthOverall = ""
    var waterlineLength = ""
    var beam = ""
    var draft = ""
    var displacement = ""
    var foretriangleHeight = ""
    var foretriangleBase = ""
    var mainsailLuff = ""
    var mainsailFoot = ""
    var sails: [SailDraft] = []

    init() {}

    init(profile: VesselProfile) {
        name = profile.name
        manufacturer = profile.manufacturer ?? ""
        modelName = profile.modelName ?? ""
        yearText = profile.constructionYear.map(String.init) ?? ""
        sailNumber = profile.sailNumber ?? ""
        registration = profile.registration ?? ""
        lengthOverall = Self.displayMetres(profile.hull.lengthOverallMeters)
        waterlineLength = Self.displayMetres(profile.hull.waterlineLengthMeters)
        beam = Self.displayMetres(profile.hull.beamMeters)
        draft = Self.displayMetres(profile.hull.draftMeters)
        displacement = Self.displayKilograms(profile.hull.displacementKilograms)
        foretriangleHeight = Self.displayMetres(profile.rig.foretriangleHeightMeters)
        foretriangleBase = Self.displayMetres(profile.rig.foretriangleBaseMeters)
        mainsailLuff = Self.displayMetres(profile.rig.mainsailLuffMeters)
        mainsailFoot = Self.displayMetres(profile.rig.mainsailFootMeters)
        sails = profile.inventory.map(SailDraft.init(record:))
    }

    var signature: EditSignature {
        EditSignature(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            manufacturer: manufacturer.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            year: parsedYear,
            sailNumber: sailNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            registration: registration.trimmingCharacters(in: .whitespacesAndNewlines),
            lengthOverall: Self.token(lengthOverall),
            waterlineLength: Self.token(waterlineLength),
            beam: Self.token(beam),
            draft: Self.token(draft),
            displacement: Self.token(displacement),
            foretriangleHeight: Self.token(foretriangleHeight),
            foretriangleBase: Self.token(foretriangleBase),
            mainsailLuff: Self.token(mainsailLuff),
            mainsailFoot: Self.token(mainsailFoot),
            sails: sails.map(\.signature)
        )
    }

    var sailSignature: [SailDraft.Signature] {
        sails.map(\.signature)
    }

    func sailRecords() -> Result<[SailRecord], VesselProfileStoreError> {
        do {
            return .success(try sails.map { try $0.record() })
        } catch let error as VesselProfileStoreError {
            return .failure(error)
        } catch {
            return .failure(.writeFailure(error.localizedDescription))
        }
    }

    func editableMetadata(name: String, year: Int?) -> Result<VesselEditableMetadata, VesselProfileStoreError> {
        do {
            return .success(VesselEditableMetadata(
                name: name,
                manufacturer: manufacturer,
                modelName: modelName,
                constructionYear: year,
                sailNumber: sailNumber,
                registration: registration,
                hull: HullDimensions(
                    lengthOverallMeters: try measurement(lengthOverall, "Length overall", unit: "metres"),
                    waterlineLengthMeters: try measurement(waterlineLength, "Waterline length", unit: "metres"),
                    beamMeters: try measurement(beam, "Beam", unit: "metres"),
                    draftMeters: try measurement(draft, "Draft", unit: "metres"),
                    displacementKilograms: try measurement(displacement, "Displacement", unit: "kilograms")
                ),
                rig: RigDimensions(
                    foretriangleHeightMeters: try measurement(foretriangleHeight, "I", unit: "metres"),
                    foretriangleBaseMeters: try measurement(foretriangleBase, "J", unit: "metres"),
                    mainsailLuffMeters: try measurement(mainsailLuff, "P", unit: "metres"),
                    mainsailFootMeters: try measurement(mainsailFoot, "E", unit: "metres")
                )
            ))
        } catch let error as VesselProfileStoreError {
            return .failure(error)
        } catch {
            return .failure(.writeFailure(error.localizedDescription))
        }
    }

    enum ParsedYear: Equatable {
        case value(Int?)
        case invalid
    }

    enum MeasurementToken: Equatable {
        case empty
        case value(Double)
        case invalid(String)
    }

    var parsedYear: ParsedYear {
        let trimmed = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .value(nil) }
        guard let year = Int(trimmed) else { return .invalid }
        return .value(year)
    }

    static func displayMetres(_ value: Double?) -> String {
        guard let value else { return "" }
        return format(value, fractionDigits: 3)
    }

    static func displayKilograms(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = numberFormatter(fractionDigits: 3, pad: false)
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    static func token(_ text: String) -> MeasurementToken {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let value = parse(trimmed), value.isFinite else { return .invalid(trimmed) }
        return .value((value * 1_000_000).rounded() / 1_000_000)
    }

    private func measurement(_ text: String, _ label: String, unit: String) throws -> Double? {
        switch Self.token(text) {
        case .empty:
            return nil
        case .invalid:
            throw VesselProfileStoreError.invalidProfileData("\(label) must be a number in \(unit).")
        case .value(let value):
            guard value > 0 else {
                throw VesselProfileStoreError.invalidProfileData("\(label) must be greater than zero.")
            }
            return value
        }
    }

    private static func parse(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        return formatter.number(from: text.trimmingCharacters(in: .whitespacesAndNewlines))?.doubleValue
    }

    private static func format(_ value: Double, fractionDigits: Int) -> String {
        numberFormatter(fractionDigits: fractionDigits, pad: true).string(from: NSNumber(value: value)) ?? ""
    }

    private static func numberFormatter(fractionDigits: Int, pad: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = pad ? fractionDigits : 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumIntegerDigits = 1
        return formatter
    }
}

struct EditSignature: Equatable {
    var name: String
    var manufacturer: String
    var modelName: String
    var year: VesselEditBuffer.ParsedYear
    var sailNumber: String
    var registration: String
    var lengthOverall: VesselEditBuffer.MeasurementToken
    var waterlineLength: VesselEditBuffer.MeasurementToken
    var beam: VesselEditBuffer.MeasurementToken
    var draft: VesselEditBuffer.MeasurementToken
    var displacement: VesselEditBuffer.MeasurementToken
    var foretriangleHeight: VesselEditBuffer.MeasurementToken
    var foretriangleBase: VesselEditBuffer.MeasurementToken
    var mainsailLuff: VesselEditBuffer.MeasurementToken
    var mainsailFoot: VesselEditBuffer.MeasurementToken
    var sails: [SailDraft.Signature]
}

struct BoatSetupDetailView: View {
    @Bindable var nmeaManager: NMEASimulator
    @State private var session = VesselLibrarySession()
    @State private var isCreating = false
    @State private var newName = ""
    @State private var newModel = ""
    @State private var newYear = ""
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            Text("Boat Profile")
                .font(.largeTitle)
            Text("Inspect a vessel here. Set as Active Vessel is what the dashboard and the simulation use. Maneuvers stay on the Dashboard Boat segment.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if nmeaManager.selectedVesselID == nil || nmeaManager.vesselStoreError != nil {
                Label(nmeaManager.activeVesselSummary, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("Vessel selection required")
            }

            HSplitView {
                library
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                detail
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(PageChrome.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if session.highlightedID == nil, let active = nmeaManager.selectedVesselID {
                session.show(active, on: nmeaManager)
            }
        }
        .alert("New Vessel", isPresented: $isCreating) {
            TextField("Name", text: $newName)
            TextField("Model", text: $newModel)
            TextField("Construction year", text: $newYear)
            Button("Create") { createVessel() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A name is required. The new vessel has no polar until a later milestone adds one.")
        }
        .alert("Rename Vessel", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Rename") { renameVessel() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this vessel?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                session.deleteHighlighted(on: nmeaManager)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The vessel is removed from the library. If it is the active vessel, simulation waits until you choose another.")
        }
        .confirmationDialog("Save changes to this vessel?", isPresented: $session.isConfirmingUnsavedChanges, titleVisibility: .visible) {
            Button("Save Changes") {
                finish(session.resolveUnsavedChanges(.save, on: nmeaManager))
            }
            Button("Discard Changes", role: .destructive) {
                finish(session.resolveUnsavedChanges(.discard, on: nmeaManager))
            }
            Button("Cancel", role: .cancel) {
                finish(session.resolveUnsavedChanges(.cancel, on: nmeaManager))
            }
        } message: {
            Text("This profile has unsaved name, model, or year changes.")
        }
        .alert("Vessel Library", isPresented: failurePresented) {
            Button("OK", role: .cancel) {
                session.dismissFailure()
            }
        } message: {
            Text(session.failureMessage ?? "The change was not saved.")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vessel Library")
                    .font(.headline)
                Spacer()
                Button("New") { leave(.create) { beginCreate() } }
                    .disabled(nmeaManager.vesselStoreError != nil)
                Button("Duplicate") {
                    if let id = session.highlightedID {
                        leave(.duplicate(id)) { duplicate() }
                    }
                }
                    .disabled(session.highlightedID == nil || nmeaManager.vesselStoreError != nil)
                Button("Delete") {
                    if let id = session.highlightedID {
                        leave(.delete(id)) { isConfirmingDelete = true }
                    }
                }
                    .disabled(!canDeleteHighlighted)
            }
            List(selection: highlightedBinding) {
                ForEach(nmeaManager.vessels) { vessel in
                    vesselRow(vessel)
                        .tag(vessel.id)
                        .tracksConsoleEdge(vessel.id == nmeaManager.vessels.first?.id, slot: "library")
                        .contextMenu {
                            Button("Set as Active Vessel") {
                                if vessel.id == session.highlightedID {
                                    session.activateHighlighted(on: nmeaManager)
                                } else {
                                    leave(.activate(vessel.id)) {
                                        session.activateHighlighted(on: nmeaManager)
                                    }
                                }
                            }
                            .disabled(nmeaManager.vesselStoreError != nil || nmeaManager.selectedVesselID == vessel.id)
                            Button("Duplicate") {
                                leave(.duplicate(vessel.id)) { duplicate() }
                            }
                            if vessel.origin == .custom {
                                Button("Rename") {
                                    leave(.rename(vessel.id)) {
                                        renameText = session.buffer.name
                                        isRenaming = true
                                    }
                                }
                                Button("Delete", role: .destructive) {
                                    leave(.delete(vessel.id)) { isConfirmingDelete = true }
                                }
                            }
                        }
                }
            }
            .accessibilityLabel("Vessel library")
        }
    }

    private var detail: some View {
        @Bindable var session = session
        return Group {
            if let profile = highlightedProfile {
                Form {
                    identitySection(profile, session: session)
                        .tracksConsoleEdge(slot: "form")
                    hullSection(profile, session: session)
                    rigSection(profile, session: session)
                    SailInventorySection(profile: profile, session: session, simulator: nmeaManager)
                    ActiveSailControls(profile: profile, target: .savedSelection, simulator: nmeaManager)
                    LabeledContent("UUID") {
                        Text(profile.id.uuidString)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Origin", value: profile.origin == .builtIn ? "Built-in" : "Custom")
                    LabeledContent("Performance", value: performanceLabel(profile))
                    LabeledContent("Simulation", value: nmeaManager.selectedVesselID == profile.id ? "Active" : "Not active")
                    Button("Save") { session.saveBuffer(on: nmeaManager) }
                        .disabled(nmeaManager.vesselStoreError != nil)
                    if profile.origin == .builtIn {
                        Text("Built-in identity, hull, and rig stay as seeded. Sails on this vessel can be edited.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Set as Active Vessel") {
                        session.activateHighlighted(on: nmeaManager)
                    }
                    .disabled(nmeaManager.vesselStoreError != nil || nmeaManager.selectedVesselID == profile.id)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    "No Vessel Selected",
                    systemImage: "sailboat",
                    description: Text("Choose a vessel in the library to inspect it. That does not change the active simulation vessel.")
                )
            }
        }
    }

    private var highlightedBinding: Binding<UUID?> {
        Binding(
            get: { session.highlightedID },
            set: { id in
                guard let id else { return }
                _ = session.requestLeave(.highlight(id), on: nmeaManager)
            }
        )
    }

    private var failurePresented: Binding<Bool> {
        Binding(
            get: { session.failureMessage != nil },
            set: { isPresented in
                if !isPresented { session.dismissFailure() }
            }
        )
    }

    private var highlightedProfile: VesselProfile? {
        guard let highlightedID = session.highlightedID else { return nil }
        return nmeaManager.vessels.first { $0.id == highlightedID }
    }

    private var canDeleteHighlighted: Bool {
        highlightedProfile?.origin == .custom && nmeaManager.vesselStoreError == nil
    }

    private func vesselRow(_ vessel: VesselProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(vessel.name)
                    .font(.body.weight(.semibold))
                Spacer()
                if nmeaManager.selectedVesselID == vessel.id {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)
                }
            }
            Text(vessel.modelName ?? "Model not recorded")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(vessel.origin == .builtIn ? "Built-in" : "Custom")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLabel(vessel))
    }

    private func rowLabel(_ vessel: VesselProfile) -> String {
        let origin = vessel.origin == .builtIn ? "Built-in" : "Custom"
        let active = nmeaManager.selectedVesselID == vessel.id ? "Active" : "Not active"
        return "\(vessel.name), \(vessel.modelName ?? "model not recorded"), \(origin), \(active)"
    }

    private func beginCreate() {
        newName = ""
        newModel = ""
        newYear = ""
        isCreating = true
    }

    private func leave(_ intent: VesselLeaveIntent, whenAllowed: () -> Void) {
        switch session.requestLeave(intent, on: nmeaManager) {
        case .allowed:
            whenAllowed()
        case .needsConfirmation:
            break
        }
    }

    private func finish(_ resolution: UnsavedResolution) {
        guard case .perform(let intent) = resolution else { return }
        switch intent {
        case .highlight:
            break
        case .create:
            beginCreate()
        case .duplicate:
            duplicate()
        case .delete:
            isConfirmingDelete = true
        case .rename:
            renameText = session.buffer.name
            isRenaming = true
        case .activate:
            session.activateHighlighted(on: nmeaManager)
        }
    }

    private func createVessel() {
        guard let year = parsedYear(newYear) else { return }
        if let created = session.createVessel(name: newName, modelName: newModel, constructionYear: year, on: nmeaManager) {
            session.show(created.id, on: nmeaManager)
        }
    }

    private func renameVessel() {
        guard let profile = highlightedProfile else { return }
        let saved = session.saveMetadata(
            id: profile.id,
            name: renameText,
            modelName: profile.modelName,
            constructionYear: profile.constructionYear,
            on: nmeaManager
        )
        if saved {
            session.show(profile.id, on: nmeaManager)
        }
    }

    private func duplicate() {
        if let copy = session.duplicateHighlighted(on: nmeaManager) {
            session.show(copy.id, on: nmeaManager)
        }
    }

    private func parsedYear(_ text: String) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Optional(nil) }
        guard let year = Int(trimmed) else {
            session.report(VesselProfileStoreError.invalidProfileData("Construction year must be a whole number."))
            return nil
        }
        return Optional(year)
    }

    private func identitySection(_ profile: VesselProfile, session: VesselLibrarySession) -> some View {
        @Bindable var session = session
        let editable = profile.origin == .custom
        return Section("Identity") {
            field("Name", text: $session.buffer.name, editable: editable, stored: profile.name)
            field("Builder", text: $session.buffer.manufacturer, editable: editable, stored: profile.manufacturer ?? "Not recorded")
            field("Model", text: $session.buffer.modelName, editable: editable, stored: profile.modelName ?? "Not recorded")
            field("Construction year", text: $session.buffer.yearText, editable: editable, stored: yearLabel(profile.constructionYear))
            field("Sail number", text: $session.buffer.sailNumber, editable: editable, stored: profile.sailNumber ?? "Not recorded")
            field("Registration", text: $session.buffer.registration, editable: editable, stored: profile.registration ?? "Not recorded")
        }
    }

    private func hullSection(_ profile: VesselProfile, session: VesselLibrarySession) -> some View {
        @Bindable var session = session
        let editable = profile.origin == .custom
        return Section("Hull") {
            measure("LOA", text: $session.buffer.lengthOverall, unit: "m", editable: editable, stored: profile.hull.lengthOverallMeters)
            measure("LWL", text: $session.buffer.waterlineLength, unit: "m", editable: editable, stored: profile.hull.waterlineLengthMeters)
            measure("Beam", text: $session.buffer.beam, unit: "m", editable: editable, stored: profile.hull.beamMeters)
            measure("Draft", text: $session.buffer.draft, unit: "m", editable: editable, stored: profile.hull.draftMeters)
            measure("Displacement", text: $session.buffer.displacement, unit: "kg", editable: editable, stored: profile.hull.displacementKilograms)
        }
    }

    private func rigSection(_ profile: VesselProfile, session: VesselLibrarySession) -> some View {
        @Bindable var session = session
        let editable = profile.origin == .custom
        return Section("Rig") {
            measure("I", text: $session.buffer.foretriangleHeight, unit: "m", editable: editable, stored: profile.rig.foretriangleHeightMeters)
            measure("J", text: $session.buffer.foretriangleBase, unit: "m", editable: editable, stored: profile.rig.foretriangleBaseMeters)
            measure("P", text: $session.buffer.mainsailLuff, unit: "m", editable: editable, stored: profile.rig.mainsailLuffMeters)
            measure("E", text: $session.buffer.mainsailFoot, unit: "m", editable: editable, stored: profile.rig.mainsailFootMeters)
            Text("I is foretriangle height. J is foretriangle base. P is mainsail luff. E is mainsail foot. A blank value is unknown.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func field(_ title: String, text: Binding<String>, editable: Bool, stored: String) -> some View {
        LabeledContent(title) {
            if editable {
                TextField(title, text: text)
            } else {
                Text(stored)
            }
        }
    }

    private func measure(_ title: String, text: Binding<String>, unit: String, editable: Bool, stored: Double?) -> some View {
        LabeledContent(title) {
            if editable {
                HStack(spacing: 6) {
                    TextField(title, text: text)
                        .multilineTextAlignment(.trailing)
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            } else if let stored {
                Text("\(unit == "kg" ? VesselEditBuffer.displayKilograms(stored) : VesselEditBuffer.displayMetres(stored)) \(unit)")
            } else {
                Text("Not recorded")
            }
        }
    }

    private func performanceLabel(_ profile: VesselProfile) -> String {
        switch profile.performance {
        case .farrDesign354:
            return "Farr Design #354"
        case .none:
            return "No polar"
        }
    }

    private func yearLabel(_ year: Int?) -> String {
        year.map(String.init) ?? "Not recorded"
    }
}

extension VesselLibrarySession {
    func dismissFailure() {
        if case .failed = lastResult {
            lastResult = .idle
        }
    }

    func report(_ error: VesselProfileStoreError) {
        lastResult = .failed(error)
    }
}
