import AppKit
import SwiftUI

/// AppKit button. SwiftUI `Button` controls inside the retained boat host are not hit-test or accessibility targets.
struct LibraryCommandButton: NSViewRepresentable {
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
