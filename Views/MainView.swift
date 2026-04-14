import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case gps, config
    case wind, hydro, compass, boat
    case dashboard, manual
}

struct MainView: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager
    
    @AppStorage("main_view.selection") private var selectedPanelRawValue: String = SidebarItem.dashboard.rawValue
    @AppStorage("main_view.console_height") private var storedConsoleHeight: Double = 28

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectedPanelRawValue) ?? .dashboard },
            set: { selectedPanelRawValue = $0?.rawValue ?? SidebarItem.dashboard.rawValue }
        )
    }

    private var consoleHeight: Binding<CGFloat> {
        Binding(
            get: { CGFloat(storedConsoleHeight) },
            set: { storedConsoleHeight = Double($0) }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Dashboard") {
                    NavigationLink(value: SidebarItem.dashboard) {
                        Label("Dashboard", systemImage: "gauge.open.with.lines.needle.33percent.and.arrow.trianglehead.from.0percent.to.50percent")
                    }
                }
                Section("Setup") {
                    NavigationLink(value: SidebarItem.config) {
                        Label("Configuration", systemImage: "gear")
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
            .navigationTitle("NMEA Simulator")
            .navigationSplitViewStyle(.prominentDetail)
        } detail: {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Top panel (dynamic height)
                    Group {
                        switch selection.wrappedValue {
                        case .dashboard:
                            DashboardView()
                        case .gps:
                            GPSConfig(nmeaManager: nmeaManager)
                        case .config:
                            ConfigurationView(nmeaManager: nmeaManager)
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
                        case .none:
                            Text("Select a panel").foregroundColor(.secondary)
                        }
                    }
                    .frame(height: max(0, geometry.size.height - consoleHeight.wrappedValue))

                    // Console Panel
                    if #available(macOS 15.0, *), selection.wrappedValue != .dashboard {
                        ConsolePanelView(
                            nmeaManager: nmeaManager,
                            consoleHeight: consoleHeight,
                            geometryHeight: geometry.size.height
                        )
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ZStack {
                    if nmeaManager.isTransmitting {
                        Button {
                            nmeaManager.stopSimulation()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .transition(.opacity)
                    } else {
                        Button {
                            nmeaManager.startSimulation()
                        } label: {
                            Label(nmeaManager.isTimerSelected ? "Start" : "Send Once", systemImage: nmeaManager.isTimerSelected ? "play.fill" : "paperplane.fill")
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: nmeaManager.isTransmitting)
            }

            ToolbarItem(placement: .status) {
                HStack(spacing: 12) {
                    Label(nmeaManager.isTransmitting ? "Transmitting" : "Idle",
                          systemImage: nmeaManager.isTransmitting ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(nmeaManager.isTransmitting ? .green : .gray)

                    if let transportStatus = nmeaManager.latestTransportStatus {
                        Label(transportStatus.message, systemImage: transportStatus.level.systemImage)
                            .font(.caption)
                            .foregroundStyle(transportStatus.level.color)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }

                    Label("\(nmeaManager.ip)", systemImage: "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                    Label("\(FormatKit.plainNumberFormatter.string(from: NSNumber(value: nmeaManager.port)) ?? "\(nmeaManager.port)")", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                .padding(.horizontal)
            }
        }
    }

    private func ensureMinimumWindowWidth(_ minWidth: CGFloat) {
        guard let window = NSApplication.shared.windows.first else { return }
        var frame = window.frame
        if frame.width < minWidth {
            frame.size.width = minWidth
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private func resizeMainWindow(_ width: CGFloat) {
        guard let window = NSApplication.shared.windows.first else { return }
        var frame = window.frame
        frame.size.width = width
        window.setFrame(frame, display: true, animate: true)
    }
}

private extension TransportStatusLevel {
    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .connected:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "questionmark.circle"
        case .connected:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }
}

extension SidebarItem: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue {
        case "gps":
            self = .gps
        case "config":
            self = .config
        case "wind":
            self = .wind
        case "hydro":
            self = .hydro
        case "compass":
            self = .compass
        case "boat":
            self = .boat
        case "dashboard":
            self = .dashboard
        case "manual":
            self = .manual
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .gps:
            return "gps"
        case .config:
            return "config"
        case .wind:
            return "wind"
        case .hydro:
            return "hydro"
        case .compass:
            return "compass"
        case .boat:
            return "boat"
        case .dashboard:
            return "dashboard"
        case .manual:
            return "manual"
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    MainView()
        .environment(NMEASimulator())
        .frame(width: 900, height: 550)
}
