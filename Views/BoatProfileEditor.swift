import AppKit
import SwiftUI

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
                    .foregroundStyle(DesignToken.Status.warning)
                    .accessibilityIdentifier("Vessel editor status")
            } else if let message = session.failureMessage {
                Text(message)
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.warning)
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
            field("Name", text: $session.buffer.name, editable: editable, stored: profile.name) { raw in
                raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A vessel name is required." : nil
            }
            field("Builder", text: $session.buffer.manufacturer, editable: editable, stored: profile.manufacturer ?? "Not recorded")
            field("Model", text: $session.buffer.modelName, editable: editable, stored: profile.modelName ?? "Not recorded")
            field("Construction year", text: $session.buffer.yearText, editable: editable, stored: yearLabel(profile.constructionYear), inputMode: .wholeNumber) { raw in
                Self.validateYearText(raw, label: "Construction year")
            }
            field("Sail number", text: $session.buffer.sailNumber, editable: editable, stored: profile.sailNumber ?? "Not recorded")
            field("Registration", text: $session.buffer.registration, editable: editable, stored: profile.registration ?? "Not recorded")
        }
    }

    private func hullSection(_ profile: VesselProfile) -> some View {
        let editable = profile.origin == .custom
        return profileBlock("Hull") {
            measure("LOA", text: $session.buffer.lengthOverall, unit: "m", editable: editable, stored: profile.hull.lengthOverallMeters, validationLabel: "Length overall", validationUnit: "metres")
            measure("LWL", text: $session.buffer.waterlineLength, unit: "m", editable: editable, stored: profile.hull.waterlineLengthMeters, validationLabel: "Waterline length", validationUnit: "metres")
            measure("Beam", text: $session.buffer.beam, unit: "m", editable: editable, stored: profile.hull.beamMeters, validationLabel: "Beam", validationUnit: "metres")
            measure("Draft", text: $session.buffer.draft, unit: "m", editable: editable, stored: profile.hull.draftMeters, validationLabel: "Draft", validationUnit: "metres")
            measure("Displacement", text: $session.buffer.displacement, unit: "kg", editable: editable, stored: profile.hull.displacementKilograms, validationLabel: "Displacement", validationUnit: "kilograms")
        }
    }

    private func rigSection(_ profile: VesselProfile) -> some View {
        let editable = profile.origin == .custom
        return profileBlock("Rig") {
            measure("I", text: $session.buffer.foretriangleHeight, unit: "m", editable: editable, stored: profile.rig.foretriangleHeightMeters, validationLabel: "I", validationUnit: "metres")
            measure("J", text: $session.buffer.foretriangleBase, unit: "m", editable: editable, stored: profile.rig.foretriangleBaseMeters, validationLabel: "J", validationUnit: "metres")
            measure("P", text: $session.buffer.mainsailLuff, unit: "m", editable: editable, stored: profile.rig.mainsailLuffMeters, validationLabel: "P", validationUnit: "metres")
            measure("E", text: $session.buffer.mainsailFoot, unit: "m", editable: editable, stored: profile.rig.mainsailFootMeters, validationLabel: "E", validationUnit: "metres")
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
    private func field(
        _ title: String,
        text: Binding<String>,
        editable: Bool,
        stored: String,
        inputMode: FormTextInputMode = .plain,
        validationError: ((String) -> String?)? = nil
    ) -> some View {
        if editable {
            FormTextRow(title: title, text: text, inputMode: inputMode, validationError: validationError)
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
    private func measure(
        _ title: String,
        text: Binding<String>,
        unit: String,
        editable: Bool,
        stored: Double?,
        validationLabel: String,
        validationUnit: String
    ) -> some View {
        if editable {
            FormTextRow(title: title, text: text, unit: unit, inputMode: .decimal) { raw in
                Self.validatePositiveDecimal(raw, label: validationLabel, unit: validationUnit)
            }
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

    private static func validateYearText(_ raw: String, label: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let year = Int(trimmed) else { return "\(label) must be a whole number." }
        guard (1800...2100).contains(year) else { return "\(label) must be from 1800 through 2100." }
        return nil
    }

    private static func validatePositiveDecimal(_ raw: String, label: String, unit: String) -> String? {
        switch VesselEditBuffer.token(raw) {
        case .empty:
            return nil
        case .invalid:
            return "\(label) must be a number in \(unit)."
        case .value(let value):
            return value > 0 ? nil : "\(label) must be greater than zero."
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
