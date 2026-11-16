import SwiftUI
import AppKit

struct MainView: View {
    var nmeaManager: NMEASimulator
    @State private var sidebarNavigation = SidebarNavigation()
    @State private var diagnostics = ExperimentDiagnosticsSession(userDefaults: .standard)
    @State private var consoleDrag = ConsoleDragTracking()
    @State private var pagePresentation = PagePresentationSession()
    @State private var gpsMapResource = GPSSelectorMapResource()
    @State private var retainedPages: Set<SidebarItem> = []
    @State private var retainedDashboardDocks = false

    @AppStorage("main_view.selection") private var selectedPanelRawValue: String = SidebarItem.dashboard.rawValue
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard },
            set: { newValue in
                let item = newValue ?? .dashboard
                selectSidebarItem(item)
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
            SidebarColumnList(
                selection: selection,
                sidebarSections: Self.sidebarSections
            )
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .background(OpaqueSidebarColumnBackground())
            .navigationSplitViewStyle(.prominentDetail)
            .transaction { $0.animation = nil }
        } detail: {
            MainDetailColumn(
                nmeaManager: nmeaManager,
                diagnostics: diagnostics,
                consoleDrag: consoleDrag,
                pagePresentation: pagePresentation,
                sidebarNavigation: sidebarNavigation,
                retainedPages: $retainedPages,
                retainedDashboardDocks: $retainedDashboardDocks
            )
            .navigationTitle("")
        }
        .environment(nmeaManager)
        .environment(\.consoleDragTracking, consoleDrag)
        .environment(\.pagePresentation, pagePresentation)
        .environment(\.sidebarNavigation, sidebarNavigation)
        .environment(\.gpsMapResource, gpsMapResource)
        .onAppear {
            NSLog("[MarineSim] MainView.onAppear panel=%@", selectedPanelRawValue)
            ConsoleHeightStorage.migrateIfNeeded()
            if selectedPanelRawValue == "config" {
                selectedPanelRawValue = SidebarItem.connection.rawValue
            }
            let item = SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard
            sidebarNavigation.selectedItem = item
            retainVisitedDestination(item)
            diagnostics.allowsWallClockLoop = (item == .diagnostics)
            #if DEBUG
            ScrollRuntimeTrace.shared.noteSelection(selectedPanelRawValue)
            #endif
        }
        .onChange(of: sidebarNavigation.selectedItem) { _, item in
            if selectedPanelRawValue != item.rawValue {
                selectedPanelRawValue = item.rawValue
            }
            #if DEBUG
            ScrollRuntimeTrace.shared.noteSelection(item.rawValue)
            #endif
        }
        .onChange(of: selectedPanelRawValue) { oldValue, value in
            let oldItem = SidebarItem(rawValue: oldValue)
            let newItem = SidebarItem(rawValue: value) ?? .dashboard
            if sidebarNavigation.selectedItem != newItem {
                sidebarNavigation.selectedItem = newItem
            }
            retainVisitedDestination(newItem)
            if oldItem == .diagnostics && newItem != .diagnostics {
                diagnostics.pauseIfRunning()
            }
            if newItem == .diagnostics {
                diagnostics.allowsWallClockLoop = true
            }
            #if DEBUG
            ScrollRuntimeTrace.shared.noteSelection(value)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            nmeaManager.persistLiveSettings()
        }
        .toolbar {
            MainWindowToolbar(
                nmeaManager: nmeaManager,
                sidebarNavigation: sidebarNavigation,
                selectedPanelRawValue: $selectedPanelRawValue
            )
        }
    }

    private static let sidebarSections: [(title: String, items: [(item: SidebarItem, systemImage: String)])] = [
        ("Dashboard", [
            (.dashboard, "gauge.open.with.lines.needle.33percent")
        ]),
        ("Setup", [
            (.connection, "network"),
            (.simulation, "slider.horizontal.3"),
            (.boat, "sailboat"),
            (.diagnostics, "waveform.path.ecg"),
            (.manual, "book.closed")
        ]),
        ("Sentences", [
            (.sentencesOverview, "checklist"),
            (.wind, "wind"),
            (.compass, "location.north.line"),
            (.hydro, "drop"),
            (.gps, "location")
        ])
    ]

    private func selectSidebarItem(_ item: SidebarItem) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if sidebarNavigation.selectedItem != item {
                sidebarNavigation.selectedItem = item
            }
            if selectedPanelRawValue != item.rawValue {
                selectedPanelRawValue = item.rawValue
            }
            retainVisitedDestination(item)
        }
    }

    private func retainVisitedDestination(_ item: SidebarItem) {
        if item == .dashboard {
            retainedDashboardDocks = true
        } else if item.retainsDestinationTree {
            retainedPages.insert(item)
        }
    }
}

private struct SidebarColumnList: View {
    var selection: Binding<SidebarItem?>
    var sidebarSections: [(title: String, items: [(item: SidebarItem, systemImage: String)])]

    var body: some View {
        List(selection: selection) {
            ForEach(sidebarSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items, id: \.item) { entry in
                        Label {
                            Text(entry.item.pageTitle)
                        } icon: {
                            Image(systemName: entry.systemImage)
                                .frame(width: 18, height: 18)
                        }
                        .tag(entry.item)
                    }
                }
            }
        }
    }
}

private struct MainDetailColumn: View {
    var nmeaManager: NMEASimulator
    var diagnostics: ExperimentDiagnosticsSession
    var consoleDrag: ConsoleDragTracking
    var pagePresentation: PagePresentationSession
    var sidebarNavigation: SidebarNavigation
    @Binding var retainedPages: Set<SidebarItem>
    @Binding var retainedDashboardDocks: Bool

    @AppStorage("main_view.selection") private var selectedPanelRawValue: String = SidebarItem.dashboard.rawValue
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    private var consoleHeight: Binding<CGFloat> {
        Binding(
            get: { CGFloat(max(0, storedLogHeight)) },
            set: { storedLogHeight = Double(max(0, $0)) }
        )
    }

    var body: some View {
        let selected = SidebarItem(rawValue: selectedPanelRawValue) ?? sidebarNavigation.selectedItem
        VStack(spacing: 0) {
            ShellContentTopSeparator()
            GeometryReader { geometry in
                let dashboardSize = selected.retainedDashboardSize(fitting: geometry.size)
                ZStack(alignment: .bottom) {
                    // One dashboard map host stays mounted at full detail size behind
                    // the detail column so its MKMapView keeps its Metal surface and tiles
                    // warm (no flash on revisit). Off the dashboard it is hidden via AppKit.
                    DashboardPageHost(nmeaManager: nmeaManager, isVisible: selected == .dashboard)
                        .frame(width: dashboardSize.width, height: dashboardSize.height)
                        .clipped()
                        .allowsHitTesting(selected == .dashboard)
                        .accessibilityHidden(selected != .dashboard)

                    // One VStack owns the active destination area on top and one shared
                    // ConsolePanelView at the bottom across every page, including Dashboard.
                    // Switching pages never tears down, recreates, or reparents the console.
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            if retainedDashboardDocks || selected == .dashboard {
                                DashboardDocksHost(nmeaManager: nmeaManager, isVisible: selected == .dashboard)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(selected == .dashboard)
                                    .accessibilityHidden(selected != .dashboard)
                            }

                            shellPages(
                                selected: selected,
                                shellVisible: selected.placesConsoleInTheShell
                            )
                            .frame(
                                width: selected.placesConsoleInTheShell ? geometry.size.width : 0,
                                height: selected.placesConsoleInTheShell ? nil : 0
                            )
                            .frame(
                                maxWidth: selected.placesConsoleInTheShell ? .infinity : 0,
                                maxHeight: selected.placesConsoleInTheShell ? .infinity : 0
                            )
                            .opacity(selected.placesConsoleInTheShell ? 1 : 0)
                            .allowsHitTesting(selected.placesConsoleInTheShell)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        ConsolePanelView(
                            nmeaManager: nmeaManager,
                            consoleHeight: consoleHeight,
                            geometryHeight: geometry.size.height
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .transaction { $0.animation = nil }
            }
        }
    }

    @ViewBuilder
    private func shellPages(selected: SidebarItem, shellVisible: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if retainedPages.contains(.connection) || selected == .connection {
                retainedHost(.connection, isActive: selected == .connection) {
                    ConnectionView(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.simulation) || selected == .simulation {
                retainedHost(.simulation, isActive: selected == .simulation) {
                    SimulationView(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.boat) || selected == .boat {
                retainedHost(.boat, isActive: selected == .boat) {
                    BoatSetupDetailView(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.diagnostics) || selected == .diagnostics {
                retainedHost(.diagnostics, isActive: selected == .diagnostics) {
                    ExperimentDiagnosticsView(session: diagnostics)
                }
            }
            if retainedPages.contains(.sentencesOverview) || selected == .sentencesOverview {
                retainedHost(.sentencesOverview, isActive: selected == .sentencesOverview) {
                    SentenceOverviewView(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.wind) || selected == .wind {
                retainedHost(.wind, isActive: selected == .wind) {
                    WindConfig(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.compass) || selected == .compass {
                retainedHost(.compass, isActive: selected == .compass) {
                    HeadingConfig(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.hydro) || selected == .hydro {
                retainedHost(.hydro, isActive: selected == .hydro) {
                    HydroConfig(nmeaManager: nmeaManager)
                }
            }
            if retainedPages.contains(.gps) || selected == .gps {
                retainedHost(.gps, isActive: selected == .gps) {
                    GPSConfig(nmeaManager: nmeaManager)
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
        case .sentencesOverview:
            SentenceOverviewView(nmeaManager: nmeaManager)
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
        private var configuredEffects: [ObjectIdentifier: NSVisualEffectView] = [:]

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            flattenSidebarEffects()
        }

        override func layout() {
            super.layout()
            if configuredEffects.isEmpty {
                flattenSidebarEffects()
            }
        }

        private func flattenSidebarEffects() {
            var current: NSView? = self
            while let view = current {
                if let effect = view as? NSVisualEffectView {
                    let key = ObjectIdentifier(effect)
                    let targetColor = NSColor.black.cgColor
                    if configuredEffects[key] !== effect
                        || effect.material != .contentBackground
                        || effect.blendingMode != .withinWindow
                        || effect.state != .active
                        || effect.layer?.backgroundColor != targetColor {
                        effect.material = .contentBackground
                        effect.blendingMode = .withinWindow
                        effect.state = .active
                        effect.wantsLayer = true
                        effect.layer?.backgroundColor = targetColor
                        configuredEffects[key] = effect
                    }
                }
                if view is NSSplitView {
                    break
                }
                current = view.superview
            }
        }
    }
}

#Preview {
    MainView(nmeaManager: NMEASimulator())
        .frame(width: 1440, height: 900)
}
