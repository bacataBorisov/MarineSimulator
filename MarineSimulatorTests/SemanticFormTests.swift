import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import MarineSimulator

@Suite
@MainActor
struct SemanticFormTests {

    @Test
    func sailSchemaCoversEveryProductionFieldAndPicker() {
        let width = ResponsiveLayout.formRowCompactWidth
        #expect(FormRowAccessibility.layoutStyle(for: width - 1) == .stacked)
        #expect(FormRowAccessibility.layoutStyle(for: width) == .compactGrid)
        #expect(FormRowAccessibility.unitStaysBesideValue)

        var fieldSets: [Set<SailEditorField.ID>] = []
        for category in SailCategory.allCases {
            var draft = SailDraft(id: UUID(), name: "Sail", category: .other)
            draft.selectCategory(category)
            let fields = SailEditorSchema.inventoryFields(for: draft.category)
            #expect(fields.isEmpty == false)
            var seen: Set<SailEditorField.ID> = []
            for field in fields {
                #expect(seen.insert(field.id).inserted)
                #expect(field.title.isEmpty == false)
                #expect(field.accessibilityLabel == field.title)
                #expect(field.accessibilityLabel == FormRowAccessibility.editorLabel(field.title))
                let expected = expectedInventoryEditor(field.id)
                #expect(field.control == expected)
                #expect(field.control.adjacentUnit == expected.adjacentUnit)
                if case .measurement(let unit) = expected {
                    #expect(unit.isEmpty == false)
                }
            }
            #expect(fields.contains { $0.control == .menu })
            fieldSets.append(seen)
        }
        #expect(Set(fieldSets).count > 1)

        let active = SailEditorSchema.activeSelectionFields()
        #expect(active.isEmpty == false)
        var activeIDs: Set<ActiveSailEditorField.ID> = []
        for field in active {
            #expect(activeIDs.insert(field.id).inserted)
            #expect(field.title.isEmpty == false)
            #expect(field.accessibilityLabel == field.title)
            let expected = expectedActiveEditor(field.id)
            #expect(field.control == expected)
            #expect(field.control.adjacentUnit == expected.adjacentUnit)
        }
        #expect(activeIDs == [.mainsail, .reef, .headsail, .downwind] as Set<ActiveSailEditorField.ID>)
    }

    @Test
    func sailPickersWriteThroughTheProductionSelectionModel() {
        var draft = SailDraft(id: UUID(), name: "Main", category: .mainsail)
        let before = Set(SailEditorSchema.inventoryFields(for: draft.category).map(\.id))
        draft.selectCategory(.symmetricSpinnaker)
        let after = Set(SailEditorSchema.inventoryFields(for: draft.category).map(\.id))
        #expect(draft.category == .symmetricSpinnaker)
        #expect(before != after)

        let mainsail = UUID()
        let headsail = UUID()
        let downwind = UUID()
        var selection = ActiveSailSelection()

        ActiveSailSelectionEdit.assignSlot(&selection, \.mainsailID, to: mainsail)
        #expect(selection == ActiveSailSelection(mainsailID: mainsail))
        #expect(ActiveSailSelectionEdit.reefPickerIsEnabled(selection))
        ActiveSailSelectionEdit.assignReef(&selection, to: .reef2)
        #expect(selection.mainsailReef == .reef2)

        ActiveSailSelectionEdit.assignSlot(&selection, \.headsailID, to: headsail)
        #expect(selection.headsailID == headsail)
        #expect(selection.mainsailID == mainsail)
        #expect(selection.downwindSailID == nil)
        #expect(selection.mainsailReef == .reef2)

        ActiveSailSelectionEdit.assignSlot(&selection, \.downwindSailID, to: downwind)
        #expect(selection.downwindSailID == downwind)
        #expect(selection.mainsailID == mainsail)
        #expect(selection.headsailID == headsail)
        #expect(selection.mainsailReef == .reef2)

        ActiveSailSelectionEdit.assignSlot(&selection, \.headsailID, to: nil)
        #expect(selection.headsailID == nil)
        #expect(selection.mainsailID == mainsail)
        #expect(selection.downwindSailID == downwind)
        #expect(selection.mainsailReef == .reef2)

        ActiveSailSelectionEdit.assignSlot(&selection, \.downwindSailID, to: nil)
        #expect(selection.downwindSailID == nil)
        #expect(selection.mainsailID == mainsail)
        #expect(selection.headsailID == nil)
        #expect(selection.mainsailReef == .reef2)

        ActiveSailSelectionEdit.assignSlot(&selection, \.mainsailID, to: nil)
        #expect(selection.mainsailID == nil)
        #expect(selection.headsailID == nil)
        #expect(selection.downwindSailID == nil)
        #expect(selection.mainsailReef == .full)
        #expect(ActiveSailSelectionEdit.reefPickerIsEnabled(selection) == false)
    }

    private func expectedInventoryEditor(_ id: SailEditorField.ID) -> SailEditorControl {
        switch id {
        case .name: .text
        case .identification: .text
        case .manufacturer: .text
        case .model: .text
        case .year: .text
        case .notes: .text
        case .source: .text
        case .category: .menu
        case .sourceStatus: .menu
        case .luff: .measurement(unit: "m")
        case .leech: .measurement(unit: "m")
        case .foot: .measurement(unit: "m")
        case .lp: .measurement(unit: "m")
        case .halfWidth: .measurement(unit: "m")
        case .area: .measurement(unit: "m²")
        case .reefCount: .reefCount
        }
    }

    private func expectedActiveEditor(_ id: ActiveSailEditorField.ID) -> SailEditorControl {
        switch id {
        case .mainsail: .menu
        case .reef: .menu
        case .headsail: .menu
        case .downwind: .menu
        }
    }

    /// Heading level and group containment come from `SettingsCardContract`, which `SettingsCard` applies.
    /// The synchronous AppKit tree does not expose SwiftUI heading traits or accessibility labels.
    /// This is not a live VoiceOver check.
    @Test
    func settingsCardUsesTheProductionHeadingAndGroupContract() {
        let semantics = SettingsCardContract.semantics(title: "Hardware Profile")
        #expect(semantics.title == "Hardware Profile")
        #expect(semantics.groupLabel == semantics.title)
        #expect(semantics.headingLevel == SettingsCardContract.headingLevel)
        #expect(semantics.headingLevel == 2)
        #expect(SettingsCardContract.heading == .h2)
        #expect(semantics.containsChildControls)
        #expect(SettingsCardContract.containsChildControls)
    }

    @Test
    func renderedSailEditorsKeepTheDraftValue() {
        let mainsail = renderedSailLabels(category: .mainsail)
        let headsail = renderedSailLabels(category: .headsail)
        #expect(mainsail.contains("Main"))
        #expect(headsail.contains("Main"))
    }

    /// Unmigrated pages keep the historical 6-point gap. It is not a `DesignToken` alias.
    @Test
    func legacySpacingStaysALiteral() {
        #expect(UIConstants.spacing == 6)
    }

    /// The status child reads the timer itself and records the enclosing `SettingsCard`.
    /// The Transmission group label is the rendered card. Static AppKit text is not the proof.
    /// This is not a VoiceOver pass.
    @Test
    func transmissionTimerStatusUpdatesInsideItsCard() {
        RetainedDestinationBodyProbe.timerStatus = ""
        RetainedDestinationBodyProbe.timerStatusCard = nil
        RetainedDestinationBodyProbe.timerStatusEvaluations = 0
        let simulator = NMEASimulator()
        simulator.isTimerSelected = true
        let host = HostedFormWindow(ConnectionView(nmeaManager: simulator), size: CGSize(width: 960, height: 760))
        defer { host.close() }

        let active = "Continuous timer mode is active."
        let disabled = "Timer disabled: Start sends one burst only."
        let showedActive = host.waitUntil {
            RetainedDestinationBodyProbe.timerStatus == active
                && RetainedDestinationBodyProbe.timerStatusCard == SetupSection.transmission.rawValue
                && accessibilityLabels(in: host.root).contains("Transmission")
        }
        #expect(
            showedActive,
            "active timer status was not inside Transmission: card=\(RetainedDestinationBodyProbe.timerStatusCard ?? "nil") probe=\(RetainedDestinationBodyProbe.timerStatus) labels=\(accessibilityLabels(in: host.root))"
        )
        let evaluations = RetainedDestinationBodyProbe.timerStatusEvaluations
        #expect(evaluations > 0)

        simulator.isTimerSelected = false
        let showedDisabled = host.waitUntil {
            RetainedDestinationBodyProbe.timerStatus == disabled
                && RetainedDestinationBodyProbe.timerStatusCard == SetupSection.transmission.rawValue
                && RetainedDestinationBodyProbe.timerStatusEvaluations > evaluations
                && accessibilityLabels(in: host.root).contains("Transmission")
        }
        #expect(
            showedDisabled,
            "disabled timer status was not inside Transmission: card=\(RetainedDestinationBodyProbe.timerStatusCard ?? "nil") probe=\(RetainedDestinationBodyProbe.timerStatus)"
        )
    }

    /// The synchronous AppKit tree exposes the child control value and the hosting group.
    /// It does not expose SwiftUI heading traits; this is not a VoiceOver pass.
    @Test
    func settingsCardKeepsTheChildControlSeparateFromTheGroup() {
        let nodes = hostedNodes(SettingsCardSample(), size: CGSize(width: 520, height: 240))
        #expect(nodes.contains { $0.role == "AXGroup" && ($0.value ?? "").isEmpty })
        #expect(nodes.contains { $0.value == "ready" && $0.role != "AXGroup" })
    }

    private func renderedSailLabels(category: SailCategory) -> [String] {
        let nodes = hostedNodes(
            SailFieldsHost(draft: SailDraft(id: UUID(), name: "Main", category: category)),
            size: CGSize(width: 760, height: 640)
        )
        return nodes.flatMap { [$0.label, $0.identifier, $0.value].compactMap { $0 } }
    }

    private func hostedNodes<V: View>(_ view: V, size: CGSize) -> [AXNode] {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        defer {
            window.orderOut(nil)
            window.close()
        }
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return axNodes(in: host)
    }
}

private struct SailFieldsHost: View {
    @State var draft: SailDraft

    var body: some View {
        SailDraftFields(draft: $draft)
            .frame(width: 720, alignment: .leading)
    }
}

private struct SettingsCardSample: View {
    @State private var note = "ready"

    var body: some View {
        SettingsCard(title: "Hardware Profile") {
            TextField("Profile note", text: $note)
            Text("Intervals follow the profile.")
        }
        .frame(width: 480, alignment: .leading)
    }
}

private struct AXNode {
    var label: String?
    var identifier: String?
    var value: String?
    var role: String?
    var subrole: String?
    var roleDescription: String?
    var headingLevel: Int
}

@MainActor
private func axNodes(in root: NSView) -> [AXNode] {
    var nodes: [AXNode] = []
    var visited: Set<ObjectIdentifier> = []

    func visitView(_ view: NSView) {
        guard visited.insert(ObjectIdentifier(view)).inserted else { return }
        nodes.append(node(from: view))
        for child in view.accessibilityChildren() ?? [] {
            if let childView = child as? NSView {
                visitView(childView)
            } else if let element = child as? NSAccessibilityElement {
                visitElement(element)
            }
        }
        for subview in view.subviews {
            visitView(subview)
        }
    }

    func visitElement(_ element: NSAccessibilityElement) {
        guard visited.insert(ObjectIdentifier(element)).inserted else { return }
        nodes.append(node(from: element))
        for child in element.accessibilityChildren() ?? [] {
            if let childView = child as? NSView {
                visitView(childView)
            } else if let nested = child as? NSAccessibilityElement {
                visitElement(nested)
            }
        }
    }

    visitView(root)
    return nodes
}

@MainActor
private func node(from view: NSView) -> AXNode {
    AXNode(
        label: view.accessibilityLabel(),
        identifier: view.accessibilityIdentifier(),
        value: controlText(of: view) ?? view.accessibilityValue() as? String,
        role: view.accessibilityRole()?.rawValue,
        subrole: view.accessibilitySubrole()?.rawValue,
        roleDescription: view.accessibilityRoleDescription(),
        headingLevel: headingLevel(of: view)
    )
}

@MainActor
private func node(from element: NSAccessibilityElement) -> AXNode {
    AXNode(
        label: element.accessibilityLabel(),
        identifier: element.accessibilityIdentifier(),
        value: element.accessibilityValue() as? String,
        role: element.accessibilityRole()?.rawValue,
        subrole: element.accessibilitySubrole()?.rawValue,
        roleDescription: element.accessibilityRoleDescription(),
        headingLevel: headingLevel(of: element)
    )
}

@MainActor
private func controlText(of view: NSView) -> String? {
    if let field = view as? NSTextField {
        let text = field.stringValue
        return text.isEmpty ? nil : text
    }
    if let button = view as? NSButton, !button.title.isEmpty {
        return button.title
    }
    return nil
}

@MainActor
private final class HostedFormWindow {
    let window: NSWindow
    let root: NSView

    init<V: View>(_ view: V, size: CGSize) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        self.window = window
        self.root = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    func waitUntil(timeout: TimeInterval = 2, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            CATransaction.flush()
            if predicate() { return true }
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

/// Group labels published by `SettingsCard`. Static `Text` storage is ignored.
@MainActor
private func accessibilityLabels(in root: NSView) -> [String] {
    var labels: [String] = []
    var seen = Set<ObjectIdentifier>()

    func visit(_ object: NSObject) {
        guard seen.insert(ObjectIdentifier(object)).inserted else { return }
        let names: [String?]
        let children: [Any]?
        if let view = object as? NSView {
            names = [view.accessibilityLabel(), view.accessibilityTitle(), view.accessibilityValue() as? String]
            children = view.accessibilityChildren()
            for subview in view.subviews {
                visit(subview)
            }
        } else if let element = object as? NSAccessibilityElement {
            names = [element.accessibilityLabel(), element.accessibilityTitle(), element.accessibilityValue() as? String]
            children = element.accessibilityChildren()
        } else {
            names = []
            children = nil
        }
        for name in names {
            guard let name, name.isEmpty == false, name.count < 80, labels.contains(name) == false else { continue }
            labels.append(name)
        }
        for child in children ?? [] {
            if let child = child as? NSObject {
                visit(child)
            }
        }
    }

    visit(root)
    return labels
}

@MainActor
private func headingLevel(of object: NSObject) -> Int {
    let value = object.accessibilityAttributeValue(.headingLevelAttribute)
    if let number = value as? NSNumber { return number.intValue }
    if let number = value as? Int { return number }
    return 0
}
