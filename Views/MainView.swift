import SwiftUI
import AppKit

struct MainView: View {
    var nmeaManager: NMEASimulator
    @State private var sidebarNavigation = SidebarNavigation()
    @State private var diagnostics = ExperimentDiagnosticsSession()
    @State private var consoleDrag = ConsoleDragTracking()
    @State private var pagePresentation = PagePresentationSession()
    @State private var gpsMapResource = GPSSelectorMapResource()
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
                    NavigationLink(value: SidebarItem.sentencesOverview) {
                        Label(SidebarItem.sentencesOverview.pageTitle, systemImage: "checklist")
                    }
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
                                if selected == .dashboard {
                                    DashboardDocksOverlay(nmeaManager: nmeaManager)
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
                selectedDestination: selection.wrappedValue ?? .dashboard,
                sidebarNavigation: sidebarNavigation,
                selectedPanelRawValue: $selectedPanelRawValue
            )
        }
    }

    @ViewBuilder
    private func shellPages(selected: SidebarItem, shellVisible: Bool) -> some View {
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
