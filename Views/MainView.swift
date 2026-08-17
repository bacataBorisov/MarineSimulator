import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case gps, connection, simulation
    case wind, hydro, compass, boat
    case dashboard, manual
}

struct MainView: View {
    var nmeaManager: NMEASimulator
    @State private var sidebarNavigation = SidebarNavigation()

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
                        Label("Boat", systemImage: "sailboat")
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
            .navigationTitle("MarineSimulator")
            .navigationSplitViewStyle(.prominentDetail)
        } detail: {
            let selected = selection.wrappedValue ?? .dashboard
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    DashboardView(isVisible: selected == .dashboard)
                        .environment(nmeaManager)
                        .opacity(selected == .dashboard ? 1 : 0)
                        .allowsHitTesting(selected == .dashboard)
                        .accessibilityHidden(selected != .dashboard)

                    if selected != .dashboard {
                        setupDetail(for: selected)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ConsolePanelView(
                            nmeaManager: nmeaManager,
                            consoleHeight: consoleHeight,
                            geometryHeight: geometry.size.height
                        )
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
        .environment(nmeaManager)
        .environment(\.sidebarNavigation, sidebarNavigation)
        .onAppear {
            NSLog("[MarineSim] MainView.onAppear panel=%@", selectedPanelRawValue)
            ConsoleHeightStorage.migrateIfNeeded()
            if selectedPanelRawValue == "config" {
                selectedPanelRawValue = SidebarItem.connection.rawValue
            }
            sidebarNavigation.selectedItem = SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard
        }
        .onChange(of: sidebarNavigation.selectedItem) { _, item in
            selectedPanelRawValue = item.rawValue
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
        case "dashboard": self = .dashboard
        case "manual": self = .manual
        default: return nil
        }
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
        case .dashboard: return "dashboard"
        case .manual: return "manual"
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    MainView(nmeaManager: NMEASimulator())
        .frame(width: 900, height: 550)
}
