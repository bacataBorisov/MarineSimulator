import SwiftUI
import AppKit

/// The dashboard keeps its own host so map layout stays independent of the shell.
@Observable
final class DashboardVisibility {
    var isVisible: Bool
    init(_ isVisible: Bool) { self.isVisible = isVisible }
}

struct DashboardMount: View {
    @Bindable var visibility: DashboardVisibility
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        DashboardView(isVisible: visibility.isVisible, nmeaManager: nmeaManager)
            .environment(nmeaManager)
    }
}

struct DashboardPageHost: NSViewRepresentable {
    var nmeaManager: NMEASimulator
    var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible)
    }

    func makeNSView(context: Context) -> NSHostingView<DashboardMount> {
        let host = NSHostingView(
            rootView: DashboardMount(visibility: context.coordinator.visibility, nmeaManager: nmeaManager)
        )
        host.sizingOptions = []
        return host
    }

    func updateNSView(_ host: NSHostingView<DashboardMount>, context: Context) {
        context.coordinator.visibility.isVisible = isVisible
    }

    final class Coordinator {
        let visibility: DashboardVisibility
        init(_ isVisible: Bool) { visibility = DashboardVisibility(isVisible) }
    }
}

/// Metrics the lifecycle tests read without knowing the hosted SwiftUI type.
protocol RetainedPageMetrics: NSView {
    var performedLayoutCount: Int { get }
}

/// Non-generic surface so a page host can be found without erasing its SwiftUI root.
protocol RetainedDestinationHosting: NSView {
    var page: SidebarItem { get }
    var isPageActive: Bool { get }
    var suppressUnchangedLayout: Bool { get set }
    var root: any RetainedPageMetrics { get }
    func setPageActive(_ active: Bool)
}

/// SwiftUI representable for one retained destination. `updateNSView` changes activity on the
/// existing host and never replaces the hosted root. The root stays the real view type.
/// `AnyView` dropped later Observation updates until a size change rebuilt the erased root.
struct RetainedDestinationHostBox<Content: View>: NSViewRepresentable {
    var page: SidebarItem
    var isActive: Bool
    var root: Content

    func makeNSView(context: Context) -> RetainedDestinationHost<Content> {
        RetainedDestinationHost(page: page, rootView: root)
    }

    func updateNSView(_ host: RetainedDestinationHost<Content>, context: Context) {
        host.setPageActive(isActive)
    }
}

/// Skips SwiftUI layout while its page is inactive, and again when activation did not change its size.
/// A selection change must not call `layoutSubtreeIfNeeded()` on this view.
final class StablePageHostingView<Content: View>: NSHostingView<Content>, RetainedPageMetrics {
    weak var pageHost: (any RetainedDestinationHosting)?
    /// Layouts that actually ran the hosted SwiftUI tree. Same-size activation does not increment it.
    private(set) var performedLayoutCount = 0
    private var laidOutSize: CGSize = .zero

    override func layout() {
        guard let pageHost, pageHost.isPageActive else { return }
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if pageHost.suppressUnchangedLayout, size == laidOutSize {
            return
        }
        pageHost.suppressUnchangedLayout = false
        laidOutSize = size
        performedLayoutCount += 1
        super.layout()
    }
}

/// AppKit boundary for a warmed retained page.
/// The hosted SwiftUI root is created once. Activity, clipping, hit testing, accessibility,
/// focus, and console-edge participation are applied here so the page body does not see selection.
final class RetainedDestinationHost<Content: View>: NSView, RetainedDestinationHosting {
    let page: SidebarItem
    let typedRoot: StablePageHostingView<Content>
    var root: any RetainedPageMetrics { typedRoot }
    private(set) var isPageActive = false
    /// Set for the activation turn. A same-size layout in that turn must not rebuild the retained root.
    var suppressUnchangedLayout = false
    private var resolvedAnchors: [ConsoleEdgeAnchorView]?
    private var firstResponderObservation: NSKeyValueObservation?

    init(page: SidebarItem, rootView: Content) {
        self.page = page
        let hosting = StablePageHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = []
        hosting.sizingOptions = []
        typedRoot = hosting
        super.init(frame: .zero)
        hosting.pageHost = self
        clipsToBounds = true
        addSubview(hosting)
        setAccessibilityElement(false)
    }

    deinit {
        firstResponderObservation?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation?.invalidate()
        firstResponderObservation = nil
        guard let window else { return }
        firstResponderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            self?.resignResponderIfInsideWhenParked()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setPageActive(_ active: Bool) {
        let changed = isPageActive != active
        isPageActive = active
        if active {
            suppressUnchangedLayout = true
        }
        // A hidden ancestor is omitted from the key-view loop, including every descendant,
        // without changing those descendants' own focus policy.
        isHidden = !active
        alphaValue = active ? 1 : 0
        setAccessibilityHidden(!active)
        root.setAccessibilityHidden(!active)
        guard changed else { return }
        if active {
            for anchor in anchors {
                anchor.setConsoleEdgeParticipation(true)
                anchor.followViewport()
            }
            DispatchQueue.main.async { [weak self] in
                self?.suppressUnchangedLayout = false
            }
        } else {
            suppressUnchangedLayout = false
            for anchor in anchors {
                anchor.setConsoleEdgeParticipation(false)
            }
            resignResponderIfInside()
        }
    }

    override func layout() {
        if isPageActive, bounds.width > 1, bounds.height > 1 {
            let fitted = CGRect(origin: .zero, size: bounds.size)
            if root.frame.size != fitted.size {
                root.frame = fitted
                root.needsLayout = true
            }
        }
        super.layout()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPageActive, bounds.contains(point) else { return nil }
        return super.hitTest(point)
    }

    private var anchors: [ConsoleEdgeAnchorView] {
        if let resolvedAnchors, resolvedAnchors.allSatisfy({ $0.superview != nil }) {
            return resolvedAnchors
        }
        let found = views(in: root).compactMap { $0 as? ConsoleEdgeAnchorView }
        if !found.isEmpty {
            resolvedAnchors = found
        }
        return found
    }

    private func resignResponderIfInsideWhenParked() {
        guard !isPageActive else { return }
        resignResponderIfInside()
    }

    private func resignResponderIfInside() {
        guard let window, let responder = window.firstResponder as? NSView else { return }
        if responder === self || responder.isDescendant(of: self) {
            window.makeFirstResponder(nil)
        }
    }

    private func views(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + views(in: $0) }
    }
}
