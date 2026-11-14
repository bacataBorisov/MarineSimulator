import AppKit
import SwiftUI

/// Setup inspection state. Highlighting a row does not change the active simulation vessel.
@Observable
final class VesselLibrarySession {
    var highlightedID: UUID?
    var editingSailID: UUID?
    var buffer = VesselEditBuffer()
    private(set) var lastResult: VesselLibraryResult = .idle
    /// Shown while typed text is not yet valid. It does not mean the last persisted profile changed.
    private(set) var validationMessage: String?
    /// Profile loads replace the buffer. Those assignments are not user edits.
    private var reloadDepth = 0
    /// Stops a successful autosave from re-entering through a published library update.
    private var isPersistingEdits = false
    private var isReloadingProfile: Bool { reloadDepth > 0 }

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
        reloadDepth += 1
        defer { reloadDepth -= 1 }
        highlightedID = id
        validationMessage = nil
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
        if hasUnsavedChanges(in: simulator) {
            switch commitEdits(on: simulator, refreshingDisplay: false) {
            case .saved:
                validationMessage = nil
            case .invalid:
                // Intermediate text never became a profile change. Leave reloads the last persisted profile.
                validationMessage = nil
            case .failed:
                return .blocked
            }
        }
        reveal(intent, on: simulator)
        return .allowed
    }

    /// Writes the current buffer when it is valid. Invalid text stays on screen and does not replace the stored profile.
    func persistValidEdits(on simulator: NMEASimulator) {
        guard isReloadingProfile == false, isPersistingEdits == false else { return }
        guard hasUnsavedChanges(in: simulator) else { return }
        isPersistingEdits = true
        defer { isPersistingEdits = false }
        switch commitEdits(on: simulator, refreshingDisplay: false) {
        case .saved:
            validationMessage = nil
        case .invalid(let message):
            validationMessage = message
            lastResult = .idle
        case .failed:
            validationMessage = nil
        }
    }

    @discardableResult
    func saveBuffer(on simulator: NMEASimulator) -> Bool {
        switch commitEdits(on: simulator, refreshingDisplay: true) {
        case .saved:
            validationMessage = nil
            return true
        case .invalid(let message):
            validationMessage = message
            lastResult = .failed(.invalidProfileData(message))
            return false
        case .failed:
            return false
        }
    }

    @discardableResult
    func createDefaultVessel(on simulator: NMEASimulator) -> VesselProfile? {
        let names = Set(simulator.vessels.map(\.name))
        var name = "Custom Vessel"
        var suffix = 2
        while names.contains(name) {
            name = "Custom Vessel \(suffix)"
            suffix += 1
        }
        reloadDepth += 1
        defer { reloadDepth -= 1 }
        guard let profile = createVessel(name: name, modelName: nil, constructionYear: nil, on: simulator) else {
            return nil
        }
        show(profile.id, on: simulator)
        return profile
    }

    private enum EditCommit {
        case saved
        case invalid(String)
        case failed
    }

    private func commitEdits(on simulator: NMEASimulator, refreshingDisplay: Bool) -> EditCommit {
        guard let profile = highlightedProfile(in: simulator) else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return .failed
        }
        let metadata: VesselEditableMetadata?
        if profile.origin == .custom {
            let trimmed = buffer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .invalid("A vessel name is required.")
            }
            guard case .value(let year) = buffer.parsedYear else {
                return .invalid("Construction year must be a whole number.")
            }
            if let year, !(1800...2100).contains(year) {
                return .invalid("Construction year must be from 1800 through 2100.")
            }
            switch buffer.editableMetadata(name: trimmed, year: year) {
            case .success(let value):
                metadata = value
            case .failure(let error):
                return .invalid(error.message)
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
            guard saved else { return .failed }
            if refreshingDisplay, let stored = highlightedProfile(in: simulator) {
                buffer = VesselEditBuffer(profile: stored)
            }
            return .saved
        case .failure(let error):
            return .invalid(error.message)
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
    case blocked
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
        if isIncompleteDecimal(trimmed) { return .invalid(trimmed) }
        guard let value = parse(trimmed), value.isFinite else { return .invalid(trimmed) }
        return .value((value * 1_000_000).rounded() / 1_000_000)
    }

    static func isIncompleteDecimal(_ text: String) -> Bool {
        text.hasSuffix(".") || text.hasSuffix("e") || text.hasSuffix("E") || text.hasSuffix("+") || text.hasSuffix("-")
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

/// Boat Profile layout. Shared spacing comes from `DesignToken`.
/// `libraryWidth` stays 320 points; it is not a shared token.
enum BoatProfileLayout {
    static let libraryWidth: CGFloat = 320
    static let outerPadding = DesignToken.Spacing.page
    static let headerStackSpacing = DesignToken.Spacing.header
    static let headerToCard = DesignToken.Spacing.inset
    static let cardPadding = DesignToken.Spacing.profileCard
    static let sectionSpacing = DesignToken.Spacing.section
    static let rowSpacing = DesignToken.Spacing.row
    static let commandSpacing = DesignToken.Spacing.row
    static let cardCornerRadius = DesignToken.Radius.compactCard
}

struct BoatSetupDetailView: View {
    @Bindable var nmeaManager: NMEASimulator
    @State private var session = VesselLibrarySession()
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.record(.boat)
        #endif
        // Fixed column. `HSplitView` installs `SplitViewChildController`, which
        // republishes min/max size on every console-height pass and exceeds
        // AppKit's Update Constraints limit.
        // The detail is a child that reads the session itself. A local `@Bindable`
        // shadow in this body does not subscribe that child, so a library click
        // can move the row without refreshing the captured profile.
        HStack(spacing: 0) {
            library
                .frame(width: BoatProfileLayout.libraryWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
            Divider()
            VesselLibraryDetail(session: session, nmeaManager: nmeaManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) {
            VesselLibrarySessionMarker(session: session)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            RetainedDestinationMarker(page: .boat)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            if session.highlightedID == nil, let active = nmeaManager.selectedVesselID {
                session.show(active, on: nmeaManager)
            }
        }
        .onChange(of: session.buffer) {
            session.persistValidEdits(on: nmeaManager)
        }
        .alert("Rename Vessel", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Rename") { renameVessel() }
            Button("Cancel", role: .cancel) {}
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
        let _ = session.highlightedID
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: BoatProfileLayout.headerStackSpacing) {
                Text("Inspect a vessel here. Set as Active Vessel is what the dashboard and the simulation use. Maneuvers stay on the Dashboard Boat segment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if nmeaManager.vesselStoreError != nil || !nmeaManager.vesselAllowsSimulation {
                    Label(nmeaManager.activeVesselSummary, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DesignToken.Status.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("Vessel selection required")
                } else if nmeaManager.selectedVesselID == nil {
                    Text(nmeaManager.activeVesselSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: BoatProfileLayout.headerToCard) {
                    Text("Vessel Library")
                        .font(.headline)
                    HStack(spacing: BoatProfileLayout.commandSpacing) {
                        LibraryCommandButton(
                            title: "New",
                            isEnabled: nmeaManager.vesselStoreError == nil,
                            action: { _ in leave(.create) { _ = session.createDefaultVessel(on: nmeaManager) } }
                        )
                        .frame(minWidth: 56, minHeight: 24)
                        LibraryCommandButton(
                            title: "Duplicate",
                            isEnabled: session.highlightedID != nil && nmeaManager.vesselStoreError == nil,
                            action: { _ in
                                if let id = session.highlightedID {
                                    leave(.duplicate(id)) { duplicate() }
                                }
                            }
                        )
                        .frame(minWidth: 72, minHeight: 24)
                        LibraryCommandButton(
                            title: "Delete",
                            isEnabled: canDeleteHighlighted,
                            action: { window in
                                guard canDeleteHighlighted, let id = session.highlightedID else { return }
                                leave(.delete(id)) { presentDelete(id: id, window: window) }
                            }
                        )
                        .frame(minWidth: 64, minHeight: 24)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BoatProfileLayout.outerPadding)

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
                                    leave(.delete(vessel.id)) { presentDelete(id: vessel.id, window: nil) }
                                }
                            }
                        }
                }
            }
            .accessibilityLabel("Vessel library")
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
                        .foregroundStyle(DesignToken.Status.success)
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

    private func leave(_ intent: VesselLeaveIntent, whenAllowed: () -> Void) {
        switch session.requestLeave(intent, on: nmeaManager) {
        case .allowed:
            whenAllowed()
        case .blocked:
            break
        }
    }

    /// Confirmation is not SwiftUI state. A missing window drops the request.
    private func presentDelete(id: UUID, window: NSWindow?) {
        guard session.highlightedID == id, highlightedProfile?.origin == .custom, nmeaManager.vesselStoreError == nil else { return }
        VesselDeletePrompt.present(vesselID: id, window: window ?? NSApp.keyWindow) {
            guard session.highlightedID == id, highlightedProfile?.origin == .custom else { return }
            session.deleteHighlighted(on: nmeaManager)
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
}

/// Detail values for the retained boat session.
/// Reads the highlight, buffer, and library in this body, so a list selection refreshes
/// the form without recreating the host. The form identity is the vessel id.
private struct VesselLibraryDetail: View {
    @Bindable var session: VesselLibrarySession
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        let highlightedID = session.highlightedID
        let _ = session.buffer
        let _ = nmeaManager.vessels
        if let highlightedID, let profile = nmeaManager.vessels.first(where: { $0.id == highlightedID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: BoatProfileLayout.sectionSpacing) {
                    identitySection(profile)
                    hullSection(profile)
                    rigSection(profile)
                    profileBlock("Sail inventory") {
                        SailInventorySection(profile: profile, session: session, simulator: nmeaManager)
                    }
                    ActiveSailControls(profile: profile, target: .savedSelection, simulator: nmeaManager)
                    profileCard {
                        CompactFormRow(title: "UUID") {
                            Text(profile.id.uuidString)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        CompactFormRow(title: "Origin") {
                            Text(profile.origin == .builtIn ? "Built-in" : "Custom")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        CompactFormRow(title: "Performance") {
                            Text(performanceLabel(profile))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(performanceLabel(profile))
                        }
                        CompactFormRow(title: "Simulation") {
                            Text(nmeaManager.selectedVesselID == profile.id ? "Active" : "Not active")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        editorStatus
                        if profile.origin == .builtIn {
                            Text("Built-in identity, hull, and rig stay as seeded. Sails on this vessel can be edited.")
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.neutral)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Set as Active Vessel") {
                        session.activateHighlighted(on: nmeaManager)
                    }
                    .disabled(nmeaManager.vesselStoreError != nil || nmeaManager.selectedVesselID == profile.id)
                }
                .id(profile.id)
                .padding(BoatProfileLayout.outerPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .tracksConsoleEdge(slot: "form")
            }
            .contentMargins(.all, 0, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                "No Vessel Selected",
                systemImage: "sailboat",
                description: Text("Choose a vessel in the library to inspect it. That does not change the active simulation vessel.")
            )
        }
    }

    private var editorStatus: some View {
        Group {
            if let message = session.validationMessage {
                Text(message)
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.error)
                    .accessibilityIdentifier("Vessel editor status")
            } else if let message = session.failureMessage {
                Text(message)
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.error)
                    .accessibilityIdentifier("Vessel editor status")
            } else if session.lastChangeSucceeded {
                Text("Saved")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .accessibilityIdentifier("Vessel editor status")
            }
        }
    }

    private func identitySection(_ profile: VesselProfile) -> some View {
        let editable = profile.origin == .custom
        return profileBlock("Identity") {
            field("Name", text: $session.buffer.name, editable: editable, stored: profile.name)
            field("Builder", text: $session.buffer.manufacturer, editable: editable, stored: profile.manufacturer ?? "Not recorded")
            field("Model", text: $session.buffer.modelName, editable: editable, stored: profile.modelName ?? "Not recorded")
            field("Construction year", text: $session.buffer.yearText, editable: editable, stored: yearLabel(profile.constructionYear))
            field("Sail number", text: $session.buffer.sailNumber, editable: editable, stored: profile.sailNumber ?? "Not recorded")
            field("Registration", text: $session.buffer.registration, editable: editable, stored: profile.registration ?? "Not recorded")
        }
    }

    private func hullSection(_ profile: VesselProfile) -> some View {
        let editable = profile.origin == .custom
        return profileBlock("Hull") {
            measure("LOA", text: $session.buffer.lengthOverall, unit: "m", editable: editable, stored: profile.hull.lengthOverallMeters)
            measure("LWL", text: $session.buffer.waterlineLength, unit: "m", editable: editable, stored: profile.hull.waterlineLengthMeters)
            measure("Beam", text: $session.buffer.beam, unit: "m", editable: editable, stored: profile.hull.beamMeters)
            measure("Draft", text: $session.buffer.draft, unit: "m", editable: editable, stored: profile.hull.draftMeters)
            measure("Displacement", text: $session.buffer.displacement, unit: "kg", editable: editable, stored: profile.hull.displacementKilograms)
        }
    }

    private func rigSection(_ profile: VesselProfile) -> some View {
        let editable = profile.origin == .custom
        return profileBlock("Rig") {
            measure("I", text: $session.buffer.foretriangleHeight, unit: "m", editable: editable, stored: profile.rig.foretriangleHeightMeters)
            measure("J", text: $session.buffer.foretriangleBase, unit: "m", editable: editable, stored: profile.rig.foretriangleBaseMeters)
            measure("P", text: $session.buffer.mainsailLuff, unit: "m", editable: editable, stored: profile.rig.mainsailLuffMeters)
            measure("E", text: $session.buffer.mainsailFoot, unit: "m", editable: editable, stored: profile.rig.mainsailFootMeters)
            Text("I is foretriangle height. J is foretriangle base. P is mainsail luff. E is mainsail foot. A blank value is unknown.")
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func profileBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BoatProfileLayout.headerToCard) {
            Text(title)
                .font(DesignToken.Typography.section)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h2)
            profileCard(content: content)
        }
    }

    private func profileCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BoatProfileLayout.rowSpacing) {
            content()
        }
        .padding(BoatProfileLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: BoatProfileLayout.cardCornerRadius, style: .continuous)
                .fill(DesignToken.Surface.card)
        }
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, editable: Bool, stored: String) -> some View {
        if editable {
            FormTextRow(title: title, text: text)
        } else {
            CompactFormRow(title: title) {
                Text(stored)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(title)
                    .accessibilityLabel(stored)
            }
        }
    }

    @ViewBuilder
    private func measure(_ title: String, text: Binding<String>, unit: String, editable: Bool, stored: Double?) -> some View {
        if editable {
            FormTextRow(title: title, text: text, unit: unit)
        } else {
            CompactFormRow(title: title) {
                if let stored {
                    let shown = "\(unit == "kg" ? VesselEditBuffer.displayKilograms(stored) : VesselEditBuffer.displayMetres(stored)) \(unit)"
                    Text(shown)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(title)
                        .accessibilityLabel(shown)
                } else {
                    Text("Not recorded")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(title)
                        .accessibilityLabel("Not recorded")
                }
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

/// AppKit button. SwiftUI `Button` controls inside the retained boat host are not hit-test or accessibility targets.
private struct LibraryCommandButton: NSViewRepresentable {
    var title: String
    var isEnabled: Bool
    var action: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.invoke(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        apply(title, enabled: isEnabled, to: button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        apply(title, enabled: isEnabled, to: button, coordinator: context.coordinator)
    }

    private func apply(_ title: String, enabled: Bool, to button: NSButton, coordinator: Coordinator) {
        button.title = title
        button.isEnabled = enabled
        button.target = coordinator
        button.action = #selector(Coordinator.invoke(_:))
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(title)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        guard size.width > 1, size.height > 1 else { return nil }
        return size
    }

    final class Coordinator: NSObject {
        var action: (NSWindow?) -> Void
        init(_ action: @escaping (NSWindow?) -> Void) { self.action = action }
        @objc func invoke(_ sender: Any?) {
            action((sender as? NSView)?.window)
        }
    }
}

/// Immediate delete confirmation for the retained Boat Profile host.
///
/// Library Delete is an AppKit button because SwiftUI buttons in that host are not hit targets.
/// `.confirmationDialog` stored its flag from that action, but the sheet is presented by SwiftUI
/// only when the retained host lays out again. Navigation is what performs that layout, so the
/// prompt appeared after leaving the page. This sheet is ordered on the click. No window means
/// no stored prompt for a later navigation pass to reveal.
@MainActor
enum VesselDeletePrompt {
    private(set) static var presentedVesselID: UUID?
    /// Clicks that reached `present` with a window. A layout pass does not increment it.
    private(set) static var requestCount = 0
    private static var confirmAction: (() -> Void)?
    private static var alert: NSAlert?

    static func present(vesselID: UUID, window: NSWindow?, onConfirm: @escaping () -> Void) {
        guard presentedVesselID == nil, let window else { return }
        requestCount += 1
        presentedVesselID = vesselID
        confirmAction = onConfirm
        let alert = NSAlert()
        alert.messageText = "Delete this vessel?"
        alert.informativeText = "The vessel is removed from the library. If it is the active vessel, simulation waits until you choose another."
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        deleteButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        self.alert = alert
        alert.beginSheetModal(for: window) { response in
            resolve(delete: response == .alertFirstButtonReturn)
        }
    }

    static func cancel() {
        _ = takeDown()
    }

    static func confirm() {
        takeDown()?()
    }

    private static func takeDown() -> (() -> Void)? {
        let action = confirmAction
        let sheet = alert?.window
        let parent = sheet?.sheetParent
        confirmAction = nil
        presentedVesselID = nil
        alert = nil
        if let sheet, let parent {
            parent.endSheet(sheet, returnCode: .cancel)
        }
        return action
    }

    private static func resolve(delete: Bool) {
        guard presentedVesselID != nil || confirmAction != nil else { return }
        let action = confirmAction
        confirmAction = nil
        presentedVesselID = nil
        alert = nil
        if delete {
            action?()
        }
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

/// Zero-size identity for the one editor session owned by the retained boat root.
struct VesselLibrarySessionMarker: NSViewRepresentable {
    var session: VesselLibrarySession

    func makeNSView(context: Context) -> VesselLibrarySessionMarkerView {
        VesselLibrarySessionMarkerView(session: session)
    }

    func updateNSView(_ nsView: VesselLibrarySessionMarkerView, context: Context) {
        nsView.session = session
    }
}

final class VesselLibrarySessionMarkerView: NSView {
    weak var session: VesselLibrarySession?

    init(session: VesselLibrarySession) {
        self.session = session
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
