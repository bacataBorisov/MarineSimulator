import SwiftUI
import AppKit

enum SidebarItem: Hashable, CaseIterable {
    case gps, connection, simulation, diagnostics
    case wind, hydro, compass, boat
    case dashboard, manual

    /// Window toolbar title. Sidebar labels use the same strings.
    var pageTitle: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .connection: return "Connection"
        case .simulation: return "Simulation"
        case .boat: return "Boat Profile"
        case .diagnostics: return "Diagnostics"
        case .manual: return "Manual"
        case .wind: return "Wind"
        case .compass: return "Compass"
        case .hydro: return "Hydro"
        case .gps: return "GPS"
        }
    }
}

struct MainView: View {
    var nmeaManager: NMEASimulator
    @State private var sidebarNavigation = SidebarNavigation()
    @State private var diagnostics = ExperimentDiagnosticsSession()
    @State private var consoleDrag = ConsoleDragTracking()
    @State private var pagePresentation = PagePresentationSession()
    /// Set on the first visit and then left true, so a later selection does not rebuild the root.
    @State private var retainedConnection = false
    @State private var retainedSimulation = false
    @State private var retainedBoat = false

    @AppStorage("main_view.selection") private var selectedPanelRawValue: String = SidebarItem.dashboard.rawValue
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard },
            set: { newValue in
                let item = newValue ?? .dashboard
                selectedPanelRawValue = item.rawValue
                sidebarNavigation.selectedItem = item
                retainVisitedDestination(item)
            }
        )
    }

    private var consoleHeight: Binding<CGFloat> {
        Binding(
            get: { CGFloat(max(0, storedLogHeight)) },
            set: { storedLogHeight = Double(max(0, $0)) }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Dashboard") {
                    NavigationLink(value: SidebarItem.dashboard) {
                        Label(SidebarItem.dashboard.pageTitle, systemImage: "gauge.open.with.lines.needle.33percent")
                    }
                }
                Section("Setup") {
                    NavigationLink(value: SidebarItem.connection) {
                        Label(SidebarItem.connection.pageTitle, systemImage: "network")
                    }
                    NavigationLink(value: SidebarItem.simulation) {
                        Label(SidebarItem.simulation.pageTitle, systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(value: SidebarItem.boat) {
                        Label(SidebarItem.boat.pageTitle, systemImage: "sailboat")
                    }
                    NavigationLink(value: SidebarItem.diagnostics) {
                        Label(SidebarItem.diagnostics.pageTitle, systemImage: "waveform.path.ecg")
                    }
                    NavigationLink(value: SidebarItem.manual) {
                        Label(SidebarItem.manual.pageTitle, systemImage: "book.closed")
                    }
                }
                Section("Sentences") {
                    NavigationLink(value: SidebarItem.wind) {
                        Label(SidebarItem.wind.pageTitle, systemImage: "wind")
                    }
                    NavigationLink(value: SidebarItem.compass) {
                        Label(SidebarItem.compass.pageTitle, systemImage: "location.north.line")
                    }
                    NavigationLink(value: SidebarItem.hydro) {
                        Label(SidebarItem.hydro.pageTitle, systemImage: "drop")
                    }
                    NavigationLink(value: SidebarItem.gps) {
                        Label(SidebarItem.gps.pageTitle, systemImage: "location")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .background(OpaqueSidebarColumnBackground())
            .navigationSplitViewStyle(.prominentDetail)
        } detail: {
            let selected = selection.wrappedValue ?? .dashboard
            VStack(spacing: 0) {
                ShellContentTopSeparator()
                GeometryReader { geometry in
                let dashboardSize = selected.retainedDashboardSize(fitting: geometry.size)
                ZStack {
                    // One dashboard identity stays mounted. Other pages propose it
                    // no size, so its map is not laid out across the detail column.
                    DashboardPageHost(nmeaManager: nmeaManager, isVisible: selected == .dashboard)
                        .frame(width: dashboardSize.width, height: dashboardSize.height)
                        .clipped()
                        .opacity(selected == .dashboard ? 1 : 0)
                        .allowsHitTesting(selected == .dashboard)
                        .accessibilityHidden(selected != .dashboard)

                    // One shell column for every non-dashboard page. Retained forms and
                    // the boat session stay in stable AppKit hosts after their first visit.
                    // Activity changes that host only. It does not pass selection into
                    // the root, so the hosted SwiftUI view is not rebuilt. Ephemeral
                    // destinations are still created by the switch and released on leave.
                    shellColumn(
                        selected: selected,
                        shellVisible: selected.placesConsoleInTheShell,
                        geometryHeight: geometry.size.height
                    )
                    .frame(
                        width: selected.placesConsoleInTheShell ? geometry.size.width : 0,
                        height: selected.placesConsoleInTheShell ? geometry.size.height : 0
                    )
                    .opacity(selected.placesConsoleInTheShell ? 1 : 0)
                    .allowsHitTesting(selected.placesConsoleInTheShell)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .transaction { $0.animation = nil }
                }
            }
            .navigationTitle(PageTitlePresentation.toolbarTitle(for: selected))
            .environment(nmeaManager)
        }
        .environment(\.consoleDragTracking, consoleDrag)
        .environment(\.pagePresentation, pagePresentation)
        .environment(\.sidebarNavigation, sidebarNavigation)
        .onAppear {
            NSLog("[MarineSim] MainView.onAppear panel=%@", selectedPanelRawValue)
            ConsoleHeightStorage.migrateIfNeeded()
            if selectedPanelRawValue == "config" {
                selectedPanelRawValue = SidebarItem.connection.rawValue
            }
            let item = SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard
            sidebarNavigation.selectedItem = item
            retainVisitedDestination(item)
            #if DEBUG
            ScrollRuntimeTrace.shared.noteSelection(selectedPanelRawValue)
            #endif
        }
        .onChange(of: sidebarNavigation.selectedItem) { _, item in
            selectedPanelRawValue = item.rawValue
            #if DEBUG
            ScrollRuntimeTrace.shared.noteSelection(item.rawValue)
            #endif
        }
        .onChange(of: selectedPanelRawValue) { _, value in
            retainVisitedDestination(SidebarItem(rawValue: value) ?? .dashboard)
            #if DEBUG
            ScrollRuntimeTrace.shared.noteSelection(value)
            #endif
        }
        .toolbar {
            MainWindowToolbar(
                nmeaManager: nmeaManager,
                sidebarNavigation: sidebarNavigation,
                selectedPanelRawValue: $selectedPanelRawValue
            )
        }
    }

    @ViewBuilder
    private func shellColumn(selected: SidebarItem, shellVisible: Bool, geometryHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if retainedConnection || selected == .connection {
                    retainedHost(.connection, isActive: selected == .connection) {
                        ConnectionView(nmeaManager: nmeaManager)
                    }
                }
                if retainedSimulation || selected == .simulation {
                    retainedHost(.simulation, isActive: selected == .simulation) {
                        SimulationView(nmeaManager: nmeaManager)
                    }
                }
                if retainedBoat || selected == .boat {
                    retainedHost(.boat, isActive: selected == .boat) {
                        BoatSetupDetailView(nmeaManager: nmeaManager)
                    }
                }
                if shellVisible && !selected.retainsDestinationTree {
                    setupDetail(for: selected)
                        .id(selected)
                        .environment(\.pageScrollIdentity, selected)
                        .onAppear { noteDestinationMounted(selected) }
                        .onDisappear { noteDestinationRemoved(selected) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if shellVisible {
                ConsolePanelView(
                    nmeaManager: nmeaManager,
                    consoleHeight: consoleHeight,
                    geometryHeight: geometryHeight
                )
            }
        }
    }

    private func retainedHost<Content: View>(
        _ page: SidebarItem,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        RetainedDestinationHostBox(
            page: page,
            isActive: isActive,
            root: content()
                .environment(\.consoleDragTracking, consoleDrag)
                .environment(\.pagePresentation, pagePresentation)
                .environment(\.pageScrollIdentity, page)
                .environment(nmeaManager)
        )
        .frame(width: isActive ? nil : 0, height: isActive ? nil : 0)
        .frame(maxWidth: isActive ? .infinity : 0, maxHeight: isActive ? .infinity : 0)
        .allowsHitTesting(isActive)
        .onAppear { noteDestinationMounted(page) }
        .onDisappear { noteDestinationRemoved(page) }
    }

    private func retainVisitedDestination(_ item: SidebarItem) {
        switch item {
        case .connection:
            retainedConnection = true
        case .simulation:
            retainedSimulation = true
        case .boat:
            retainedBoat = true
        default:
            break
        }
    }

    private func noteDestinationMounted(_ item: SidebarItem) {
        #if DEBUG
        ScrollRuntimeTrace.shared.noteMounted(item.rawValue)
        #else
        _ = item
        #endif
    }

    private func noteDestinationRemoved(_ item: SidebarItem) {
        #if DEBUG
        ScrollRuntimeTrace.shared.noteRemoved(item.rawValue)
        #else
        _ = item
        #endif
    }

    @ViewBuilder
    private func setupDetail(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            EmptyView()
        case .gps:
            GPSConfig(nmeaManager: nmeaManager)
        case .connection:
            ConnectionView(nmeaManager: nmeaManager)
        case .simulation:
            SimulationView(nmeaManager: nmeaManager)
        case .manual:
            ManualView()
        case .wind:
            WindConfig(nmeaManager: nmeaManager)
        case .hydro:
            HydroConfig(nmeaManager: nmeaManager)
        case .compass:
            HeadingConfig(nmeaManager: nmeaManager)
        case .boat:
            BoatSetupDetailView(nmeaManager: nmeaManager)
        case .diagnostics:
            ExperimentDiagnosticsView(session: diagnostics)
        }
    }
}

/// `NavigationSplitView` installs an `NSVisualEffectView` sidebar material. Hide that
/// vibrancy inside this column so the list can be solid black like the dashboard rails.
private struct OpaqueSidebarColumnBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SidebarMaterialFlattener()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SidebarMaterialFlattener: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            flattenSidebarEffects()
        }

        override func layout() {
            super.layout()
            flattenSidebarEffects()
        }

        private func flattenSidebarEffects() {
            var current: NSView? = self
            while let view = current {
                if let effect = view as? NSVisualEffectView {
                    effect.material = .contentBackground
                    effect.blendingMode = .withinWindow
                    effect.state = .active
                    effect.wantsLayer = true
                    effect.layer?.backgroundColor = NSColor.black.cgColor
                }
                if view is NSSplitView {
                    break
                }
                current = view.superview
            }
        }
    }
}

/// Toolbar observation of this simulator suppresses later updates in the root hosting view.
/// The dashboard keeps its own host so reads in its body still invalidate.
@Observable
private final class DashboardVisibility {
    var isVisible: Bool
    init(_ isVisible: Bool) { self.isVisible = isVisible }
}

private struct DashboardMount: View {
    @Bindable var visibility: DashboardVisibility
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        DashboardView(isVisible: visibility.isVisible, nmeaManager: nmeaManager)
            .environment(nmeaManager)
    }
}

private struct DashboardPageHost: NSViewRepresentable {
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

private struct MainWindowToolbar: ToolbarContent {
    var nmeaManager: NMEASimulator
    var sidebarNavigation: SidebarNavigation
    @Binding var selectedPanelRawValue: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            TransmissionToolbarButton(nmeaManager: nmeaManager)
        }

        ToolbarItem(placement: .status) {
            TransportStatusToolbarButton(nmeaManager: nmeaManager) {
                sidebarNavigation.select(.connection)
                selectedPanelRawValue = SidebarItem.connection.rawValue
            }
        }
    }
}

private struct TransmissionToolbarButton: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        Button {
            if nmeaManager.isTransmitting {
                nmeaManager.stopSimulation()
            } else {
                nmeaManager.startSimulation()
            }
        } label: {
            Label(
                nmeaManager.isTransmitting ? "Stop" : "Start",
                systemImage: nmeaManager.isTransmitting ? "stop.fill" : "play.fill"
            )
        }
        .help(nmeaManager.isTransmitting ? "Stop sending data (⌘R)" : "Start sending data (⌘R)")
        .keyboardShortcut("r", modifiers: .command)
    }
}

private struct TransportStatusToolbarButton: View {
    @Bindable var nmeaManager: NMEASimulator
    var openConnection: () -> Void

    var body: some View {
        let transportMessage = nmeaManager.latestTransportStatus?.message
        let summary = PrimaryOutputSummary.label(for: nmeaManager)
        let activity = nmeaManager.isTransmitting ? "Transmitting" : "Idle"
        let statusLine = [activity, transportMessage, summary].compactMap { $0 }.joined(separator: " · ")
        Button {
            openConnection()
        } label: {
            Label(statusLine,
                  systemImage: nmeaManager.isTransmitting ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(nmeaManager.isTransmitting ? DesignToken.Status.success : DesignToken.Status.neutral)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel(statusLine)
    }
}

/// How a sidebar destination stays mounted.
/// The GPS map resource is named here and is not installed in this slice.
enum SidebarDestinationLifecycle: Equatable {
    /// Dashboard map host stays mounted and is proposed zero size off the dashboard.
    case retainedDashboardMap
    /// Complete page root stays in one stable AppKit host after the first visit.
    case retainedForm
    /// Complete page root and its one editor session stay in one stable AppKit host.
    case retainedSessionView
    /// A map resource may stay mounted while its page shell does not. Not installed yet.
    case retainedMapResource
    /// The switch creates the page and releases it on leave.
    case ephemeral
}

extension SidebarItem: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue {
        case "gps": self = .gps
        case "config", "connection": self = .connection
        case "simulation": self = .simulation
        case "wind": self = .wind
        case "hydro": self = .hydro
        case "compass": self = .compass
        case "boat": self = .boat
        case "diagnostics": self = .diagnostics
        case "dashboard": self = .dashboard
        case "manual": self = .manual
        default: return nil
        }
    }

    /// The dashboard draws its own console over the map. Every other page uses the shell column.
    var placesConsoleInTheShell: Bool {
        self != .dashboard
    }

    /// Stable AppKit root after the first visit. The GPS map resource is classified
    /// separately and is not mounted in this slice, so that page still leaves.
    var retainsDestinationTree: Bool {
        switch lifecycle {
        case .retainedForm, .retainedSessionView:
            return true
        case .retainedDashboardMap, .retainedMapResource, .ephemeral:
            return false
        }
    }

    /// Retention class for this destination. Dashboard keeps its existing map host.
    /// GPS names a map resource that this slice does not install.
    /// Manual stays ephemeral: parking its scrolled topics list asserts in SwiftUI.
    var lifecycle: SidebarDestinationLifecycle {
        switch self {
        case .dashboard:
            return .retainedDashboardMap
        case .connection, .simulation:
            return .retainedForm
        case .boat:
            return .retainedSessionView
        case .gps:
            return .retainedMapResource
        case .diagnostics, .wind, .hydro, .compass, .manual:
            return .ephemeral
        }
    }

    /// Full detail size on the dashboard. Zero on every other page so the retained
    /// dashboard and its map stay mounted without joining that page's layout.
    func retainedDashboardSize(fitting detail: CGSize) -> CGSize {
        self == .dashboard ? detail : .zero
    }

    var rawValue: String {
        switch self {
        case .gps: return "gps"
        case .connection: return "connection"
        case .simulation: return "simulation"
        case .wind: return "wind"
        case .hydro: return "hydro"
        case .compass: return "compass"
        case .boat: return "boat"
        case .diagnostics: return "diagnostics"
        case .dashboard: return "dashboard"
        case .manual: return "manual"
        }
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
private struct RetainedDestinationHostBox<Content: View>: NSViewRepresentable {
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

#Preview(traits: .sizeThatFitsLayout) {
    MainView(nmeaManager: NMEASimulator())
        .frame(width: 900, height: 550)
}
