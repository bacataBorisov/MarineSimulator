import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselLibraryEditorTests {

    @Test
    func createEditAndDuplicateKeepIdentityAndLeaveTheOriginalAlone() throws {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        let created = try #require(session.createVessel(name: "  Skiff  ", modelName: "Custom 28", constructionYear: 2024, on: simulator))
        #expect(session.lastChangeSucceeded)
        #expect(created.name == "Skiff")
        #expect(created.modelName == "Custom 28")
        #expect(created.constructionYear == 2024)
        #expect(created.performance == VesselProfile.Performance.none)
        #expect(created.origin == .custom)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(session.highlightedID == created.id)

        let saved = session.saveMetadata(id: created.id, name: "Skiff II", modelName: "Custom 29", constructionYear: 2025, on: simulator)
        #expect(saved)
        let edited = try #require(simulator.vessels.first { $0.id == created.id })
        #expect(edited.id == created.id)
        #expect(edited.name == "Skiff II")
        #expect(edited.modelName == "Custom 29")
        #expect(edited.performance == VesselProfile.Performance.none)

        session.highlight(BuiltInVesselID.extasy)
        let extasyCopy = try #require(session.duplicateHighlighted(on: simulator))
        #expect(extasyCopy.id != BuiltInVesselID.extasy)
        #expect(extasyCopy.name == "Extasy Copy")
        #expect(extasyCopy.performance == VesselProfile.Performance.none)
        #expect(extasyCopy.origin == .custom)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.performance == .farrDesign354)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(session.highlightedID == extasyCopy.id)

        session.highlight(created.id)
        let customCopy = try #require(session.duplicateHighlighted(on: simulator))
        #expect(customCopy.id != created.id)
        #expect(customCopy.performance == VesselProfile.Performance.none)
        #expect(simulator.vessels.first { $0.id == created.id }?.name == "Skiff II")
    }

    @Test
    func newVesselPersistsAUniqueEditableProfileImmediately() throws {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        let first = try #require(session.createDefaultVessel(on: simulator))
        #expect(first.name == "Custom Vessel")
        #expect(first.origin == .custom)
        #expect(first.performance == VesselProfile.Performance.none)
        #expect(first.id != BuiltInVesselID.extasy)
        #expect(session.highlightedID == first.id)
        #expect(session.buffer.name == "Custom Vessel")
        #expect(session.lastChangeSucceeded)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        let second = try #require(session.createDefaultVessel(on: simulator))
        #expect(second.id != first.id)
        #expect(second.name == "Custom Vessel 2")
        #expect(simulator.vessels.filter { $0.name == first.name }.count == 1)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.origin == .builtIn)
    }

    @Test
    func builtInProfilesStayProtectedAndHighlightingDoesNotActivate() {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        session.highlight(BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(session.highlightedID == BuiltInVesselID.nimana)

        #expect(session.saveMetadata(id: BuiltInVesselID.nimana, name: "Other", modelName: nil, constructionYear: nil, on: simulator) == false)
        #expect(session.lastChangeSucceeded == false)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.nimana }?.name == "Nimana")
        #expect(session.deleteHighlighted(on: simulator) == false)
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.nimana })
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func deletingTheActiveCustomVesselRequiresAnExplicitReplacement() throws {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: nil, constructionYear: nil, on: simulator))
        session.activateHighlighted(on: simulator)
        #expect(simulator.selectedVesselID == custom.id)

        #expect(session.deleteHighlighted(on: simulator))
        #expect(simulator.selectedVesselID == nil)
        #expect(simulator.activeVesselName == "No vessel")
        #expect(simulator.activeVesselSummary.contains(custom.id.uuidString))
        #expect(simulator.vesselAllowsSimulation == false)
        if case .unresolved(let reference) = simulator.activeVesselState {
            #expect(reference == custom.id.uuidString)
        } else {
            Issue.record("Expected the deleted id to stay unresolved")
        }

        session.highlight(BuiltInVesselID.extasy)
        #expect(simulator.selectedVesselID == nil)
        session.activateHighlighted(on: simulator)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(simulator.vesselAllowsSimulation)
    }

    @Test
    func aFailedWriteIsNotReportedAsSavedAndTheDashboardUsesTheSameActiveVessel() throws {
        let store = RejectingVesselStore()
        let defaults = isolatedLibraryDefaults()
        let simulator = NMEASimulator(userDefaults: defaults, vesselStore: store)
        let session = VesselLibrarySession()
        store.rejectWrites = true
        let before = simulator.vessels.map(\.id)
        let created = session.createVessel(name: "Skiff", modelName: "X", constructionYear: 2020, on: simulator)
        #expect(created == nil)
        #expect(session.lastChangeSucceeded == false)
        #expect(session.failureMessage?.contains("could not be saved") == true)
        #expect(simulator.vessels.map(\.id) == before)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        store.rejectWrites = false
        session.highlight(BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        session.activateHighlighted(on: simulator)
        #expect(simulator.selectedVesselID == BuiltInVesselID.nimana)
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        let restored = NMEASimulator(userDefaults: defaults, vesselStore: store)
        #expect(restored.selectedVesselID == BuiltInVesselID.nimana)
    }

    /// Geometry and retained controls only. Grouped-form labels are not `NSTextField`
    /// string values, and those fields report no AppKit accessibility label, so a
    /// single visible label and VoiceOver labeling stay manual runtime checks.
    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func boatProfileKeepsAFixedLibraryColumnAndCommandControls() throws {
        let simulator = librarySimulator()
        let created = try #require(VesselLibrarySession().createDefaultVessel(on: simulator))
        simulator.selectVessel(created.id)

        let host = NSHostingView(rootView: BoatSetupDetailView(nmeaManager: simulator))
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 1180, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.contentView = host
        host.autoresizingMask = [.width, .height]
        defer {
            window.orderOut(nil)
            window.close()
        }
        window.orderFrontRegardless()

        let ready = waitUntil(host: host) {
            host.layoutSubtreeIfNeeded()
            guard let columns = boatColumns(in: host) else { return false }
            return columns.detail.width > columns.library.width
                && editableField(in: host, value: created.name) != nil
        }
        try #require(ready, "boat columns were not ready: \(textDump(host))")

        let columns = try #require(boatColumns(in: host))
        #expect(views(in: host).contains { $0 is NSSplitView } == false)
        #expect(abs(columns.library.width - 320) < 24)
        #expect(columns.detail.minX >= columns.library.maxX - 8)
        #expect(columns.detail.width > columns.library.width)
        #expect(columns.library.height > 160)
        #expect(columns.detail.height > 160)
        #expect(views(in: host).contains { abs($0.bounds.width - 320) < 2 && $0.bounds.height > 200 })

        let nameEditor = try #require(editableField(in: host, value: created.name))
        let editorFrame = nameEditor.convert(nameEditor.bounds, to: nil)
        #expect(editorFrame.minX >= columns.library.maxX - 8)
        #expect(editorFrame.maxX <= columns.detail.maxX + 2)

        for title in ["New", "Duplicate", "Delete"] {
            let button = try #require(commandButton(title, in: host), "missing \(title)")
            #expect(button.accessibilityLabel() == title)
            #expect(button.accessibilityIdentifier() == title)
            #expect(button.isEnabled)
        }
        #expect(views(in: host).contains { $0 is VesselLibrarySessionMarkerView })
    }

    @Test @MainActor
    func deletePromptIsNotQueuedWithoutAWindow() {
        VesselDeletePrompt.cancel()
        let before = VesselDeletePrompt.requestCount
        VesselDeletePrompt.present(vesselID: UUID(), window: nil) {
            Issue.record("Delete confirmation ran without a window")
        }
        #expect(VesselDeletePrompt.requestCount == before)
        #expect(VesselDeletePrompt.presentedVesselID == nil)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func enabledDeletePresentsConfirmationImmediatelyAndCancelLeavesTheProfile() throws {
        let simulator = librarySimulator()
        let created = try #require(VesselLibrarySession().createDefaultVessel(on: simulator))
        simulator.selectVessel(created.id)
        let (window, host) = presentedBoatProfile(simulator)
        defer { releaseBoatProfile(window) }
        let ready = waitUntil(host: host) {
            commandButton("Delete", in: host)?.isEnabled == true
        }
        try #require(ready, "Delete was not enabled: \(textDump(host))")

        let before = VesselDeletePrompt.requestCount
        try #require(commandButton("Delete", in: host)).performClick(nil)
        #expect(VesselDeletePrompt.requestCount == before + 1)
        #expect(VesselDeletePrompt.presentedVesselID == created.id)
        #expect(simulator.vessels.contains { $0.id == created.id })
        #expect(simulator.selectedVesselID == created.id)

        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        #expect(VesselDeletePrompt.requestCount == before + 1)
        #expect(VesselDeletePrompt.presentedVesselID == created.id)

        VesselDeletePrompt.cancel()
        #expect(VesselDeletePrompt.presentedVesselID == nil)
        #expect(simulator.vessels.contains { $0.id == created.id })
        #expect(simulator.selectedVesselID == created.id)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        #expect(VesselDeletePrompt.presentedVesselID == nil)
        #expect(VesselDeletePrompt.requestCount == before + 1)
        #expect(window.attachedSheet == nil)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func confirmingDeleteRemovesOnlyThePresentedCustomVessel() throws {
        let simulator = librarySimulator()
        let created = try #require(VesselLibrarySession().createDefaultVessel(on: simulator))
        simulator.selectVessel(created.id)
        let (window, host) = presentedBoatProfile(simulator)
        defer { releaseBoatProfile(window) }
        let ready = waitUntil(host: host) {
            commandButton("Delete", in: host)?.isEnabled == true
        }
        try #require(ready, "Delete was not enabled: \(textDump(host))")

        try #require(commandButton("Delete", in: host)).performClick(nil)
        #expect(VesselDeletePrompt.presentedVesselID == created.id)
        VesselDeletePrompt.confirm()
        #expect(VesselDeletePrompt.presentedVesselID == nil)
        #expect(simulator.vessels.contains { $0.id == created.id } == false)
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.extasy })
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.nimana })
        #expect(simulator.selectedVesselID == nil)
        #expect(simulator.vesselAllowsSimulation == false)
        if case .unresolved(let reference) = simulator.activeVesselState {
            #expect(reference == created.id.uuidString)
        } else {
            Issue.record("Expected the deleted id to stay unresolved")
        }

        let after = VesselDeletePrompt.requestCount
        VesselDeletePrompt.confirm()
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        #expect(VesselDeletePrompt.requestCount == after)
        #expect(VesselDeletePrompt.presentedVesselID == nil)
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.extasy })
        #expect(window.attachedSheet == nil)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func builtInDeleteStaysDisabledAndDoesNotPresentConfirmation() throws {
        let simulator = librarySimulator()
        let (window, host) = presentedBoatProfile(simulator)
        defer { releaseBoatProfile(window) }
        let ready = waitUntil(host: host) {
            commandButton("Delete", in: host) != nil
        }
        try #require(ready, "Delete was not created: \(textDump(host))")
        let button = try #require(commandButton("Delete", in: host))
        #expect(button.isEnabled == false)
        let before = VesselDeletePrompt.requestCount
        button.performClick(nil)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        #expect(button.isEnabled == false)
        #expect(VesselDeletePrompt.requestCount == before)
        #expect(VesselDeletePrompt.presentedVesselID == nil)
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.extasy })
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(window.attachedSheet == nil)
    }
}

private final class RejectingVesselStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    var rejectWrites = false

    func loadDocument() throws -> VesselProfileDocument? {
        document
    }

    func saveDocument(_ document: VesselProfileDocument) throws {
        if rejectWrites {
            throw VesselProfileStoreError.writeFailure("disk full")
        }
        self.document = document
    }
}

private func librarySimulator() -> NMEASimulator {
    NMEASimulator(userDefaults: isolatedLibraryDefaults(), vesselStore: InMemoryVesselProfileStore())
}

private func isolatedLibraryDefaults() -> UserDefaults {
    let suite = "VesselLibrary.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func presentedBoatProfile(_ simulator: NMEASimulator) -> (window: NSWindow, host: NSHostingView<BoatSetupDetailView>) {
    VesselDeletePrompt.cancel()
    let host = NSHostingView(rootView: BoatSetupDetailView(nmeaManager: simulator))
    let window = NSWindow(
        contentRect: NSRect(x: -4000, y: -4000, width: 1180, height: 900),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.alphaValue = 0
    window.contentView = host
    host.autoresizingMask = [.width, .height]
    window.orderFrontRegardless()
    return (window, host)
}

@MainActor
private func releaseBoatProfile(_ window: NSWindow) {
    VesselDeletePrompt.cancel()
    if let sheet = window.attachedSheet {
        window.endSheet(sheet, returnCode: .cancel)
    }
    window.orderOut(nil)
    window.close()
}

@MainActor
private func waitUntil(host: NSView, timeout: TimeInterval = 5, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        host.layoutSubtreeIfNeeded()
        if predicate() { return true }
        if Date() >= deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }
}

@MainActor
private func boatColumns(in root: NSView) -> (library: NSRect, detail: NSRect)? {
    guard let table = views(in: root).compactMap({ $0 as? NSTableView }).first(where: {
        $0.bounds.width > 160 && $0.bounds.height > 80 && $0.isHiddenOrHasHiddenAncestor == false
    }), let libraryScroll = table.enclosingScrollView else { return nil }
    let library = libraryScroll.convert(libraryScroll.bounds, to: nil)
    let detailCandidates = views(in: root).compactMap { $0 as? NSScrollView }.filter { scroll in
        let frame = scroll.convert(scroll.bounds, to: nil)
        return frame.minX >= library.maxX - 8
            && frame.width > library.width
            && frame.height > 160
            && scroll !== libraryScroll
    }
    guard let detailScroll = detailCandidates.max(by: { $0.bounds.width < $1.bounds.width }) else { return nil }
    return (library, detailScroll.convert(detailScroll.bounds, to: nil))
}

@MainActor
private func visibleFields(in root: NSView) -> [NSTextField] {
    views(in: root).compactMap { view in
        guard let field = view as? NSTextField else { return nil }
        guard field.isHiddenOrHasHiddenAncestor == false, field.bounds.width > 2, field.bounds.height > 2 else { return nil }
        return field
    }
}

@MainActor
private func editableField(in root: NSView, value: String) -> NSTextField? {
    visibleFields(in: root).first { field in
        field.isEditable && field.stringValue == value && field.bounds.width > 20
    }
}

@MainActor
private func commandButton(_ title: String, in root: NSView) -> NSButton? {
    views(in: root).compactMap { $0 as? NSButton }.first { button in
        button.title == title && button.bounds.width > 2 && button.bounds.height > 2 && button.isHiddenOrHasHiddenAncestor == false
    }
}

@MainActor
private func textDump(_ root: NSView) -> String {
    let columns = boatColumns(in: root).map { "library \(Int($0.library.width))x\(Int($0.library.height)) detail \(Int($0.detail.width))x\(Int($0.detail.minX))" } ?? "no-columns"
    let fields = visibleFields(in: root).prefix(40).map { field in
        "\(field.stringValue.prefix(24))/\(field.accessibilityLabel() ?? "-") e=\(field.isEditable)"
    }.joined(separator: " | ")
    return "\(columns) \(fields)"
}

@MainActor
private func views(in root: NSView) -> [NSView] {
    root.subviews.flatMap { [$0] + views(in: $0) }
}
