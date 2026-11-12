import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case gps, connection, simulation, diagnostics
    case wind, hydro, compass, boat
    case dashboard, manual
}

struct MainView: View {
    var nmeaManager: NMEASimulator
    @State private var sidebarNavigation = SidebarNavigation()
    @State private var diagnostics = ExperimentDiagnosticsSession()
    @State private var consoleDrag = ConsoleDragTracking()
    @State private var pagePresentation = PagePresentationSession()

    @AppStorage("main_view.selection") private var selectedPanelRawValue: String = SidebarItem.dashboard.rawValue
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard },
            set: { newValue in
                let item = newValue ?? .dashboard
                selectedPanelRawValue = item.rawValue
                sidebarNavigation.selectedItem = item
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
                        Label("Dashboard", systemImage: "gauge.open.with.lines.needle.33percent")
                    }
                }
                Section("Setup") {
                    NavigationLink(value: SidebarItem.connection) {
                        Label("Connection", systemImage: "network")
                    }
                    NavigationLink(value: SidebarItem.simulation) {
                        Label("Simulation", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(value: SidebarItem.boat) {
                        Label("Boat Profile", systemImage: "sailboat")
                    }
                    NavigationLink(value: SidebarItem.diagnostics) {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink(value: SidebarItem.manual) {
                        Label("Manual", systemImage: "book.closed")
                    }
                }
                Section("Sentences") {
                    NavigationLink(value: SidebarItem.wind) {
                        Label("Wind", systemImage: "wind")
                    }
                    NavigationLink(value: SidebarItem.compass) {
                        Label("Compass", systemImage: "location.north.line")
                    }
                    NavigationLink(value: SidebarItem.hydro) {
                        Label("Hydro", systemImage: "drop")
                    }
                    NavigationLink(value: SidebarItem.gps) {
                        Label("GPS", systemImage: "location")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .background(OpaqueSidebarColumnBackground())
            .navigationTitle("MarineSimulator")
            .navigationSplitViewStyle(.prominentDetail)
        } detail: {
            let selected = selection.wrappedValue ?? .dashboard
            GeometryReader { geometry in
                let dashboardSize = selected.retainedDashboardSize(fitting: geometry.size)
                ZStack {
                    // One dashboard identity stays mounted. Other pages propose it
                    // no size, so its map is not laid out across the detail column.
                    DashboardView(isVisible: selected == .dashboard)
                        .environment(nmeaManager)
                        .frame(width: dashboardSize.width, height: dashboardSize.height)
                        .clipped()
                        .opacity(selected == .dashboard ? 1 : 0)
                        .allowsHitTesting(selected == .dashboard)
                        .accessibilityHidden(selected != .dashboard)

                    if selected.placesConsoleInTheShell {
                        // The dashboard keeps its console inside the map column.
                        // Every other page gets one shell column so the console
                        // takes height instead of covering the page.
                        VStack(spacing: 0) {
                            setupDetail(for: selected)
                                .id(selected)
                                .environment(\.pageScrollIdentity, selected)
                                .onAppear {
                                    #if DEBUG
                                    ScrollRuntimeTrace.shared.noteMounted(selected.rawValue)
                                    #endif
                                }
                                .onDisappear {
                                    #if DEBUG
                                    ScrollRuntimeTrace.shared.noteRemoved(selected.rawValue)
                                    #endif
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            ConsolePanelView(
                                nmeaManager: nmeaManager,
                                consoleHeight: consoleHeight,
                                geometryHeight: geometry.size.height
                            )
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .transaction { $0.animation = nil }
            }
        }
        .environment(nmeaManager)
        .environment(\.consoleDragTracking, consoleDrag)
        .environment(\.pagePresentation, pagePresentation)
        .environment(\.sidebarNavigation, sidebarNavigation)
        .onAppear {
            NSLog("[MarineSim] MainView.onAppear panel=%@", selectedPanelRawValue)
            ConsoleHeightStorage.migrateIfNeeded()
            if selectedPanelRawValue == "config" {
                selectedPanelRawValue = SidebarItem.connection.rawValue
            }
            sidebarNavigation.selectedItem = SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard
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

private struct MainWindowToolbar: ToolbarContent {
    @Bindable var nmeaManager: NMEASimulator
    var sidebarNavigation: SidebarNavigation
    @Binding var selectedPanelRawValue: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
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

        ToolbarItem(placement: .status) {
            Button {
                sidebarNavigation.select(.connection)
                selectedPanelRawValue = SidebarItem.connection.rawValue
            } label: {
                HStack(spacing: 12) {
                    Label(nmeaManager.isTransmitting ? "Transmitting" : "Idle",
                          systemImage: nmeaManager.isTransmitting ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(nmeaManager.isTransmitting ? .green : .secondary)

                    if let transportStatus = nmeaManager.latestTransportStatus {
                        Label(transportStatus.message, systemImage: transportStatus.level.systemImage)
                            .font(.caption)
                            .foregroundStyle(transportStatus.level.color)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }

                    Text(PrimaryOutputSummary.label(for: nmeaManager))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }
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

#Preview(traits: .sizeThatFitsLayout) {
    MainView(nmeaManager: NMEASimulator())
        .frame(width: 900, height: 550)
}
