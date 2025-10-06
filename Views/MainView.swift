import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case gps, config
    case wind, hydro, compass
    case dashboard
}

struct MainView: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager
    
    @State private var selection: SidebarItem? = .dashboard

    @State private var consoleHeight: CGFloat = 28

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Dashboard") {
                    NavigationLink(value: SidebarItem.dashboard) {
                        Label("Dashboard", systemImage: "gauge.open.with.lines.needle.33percent.and.arrow.trianglehead.from.0percent.to.50percent")
                    }
                }
                Section("Setup") {
                    NavigationLink(value: SidebarItem.config) {
                        Label("Configuration", systemImage: "gear")
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
                        switch selection {
                        case .dashboard:
                            DashboardView()
                        case .gps:
                            GPSConfig(nmeaManager: nmeaManager)
                        case .config:
                            ConfigurationView(nmeaManager: nmeaManager)
                        case .wind:
                            WindConfig(nmeaManager: nmeaManager)
                        case .hydro:
                            HydroConfig(nmeaManager: nmeaManager)
                        case .compass:
                            HeadingConfig(nmeaManager: nmeaManager)
                        case .none:
                            Text("Select a panel").foregroundColor(.secondary)
                        }
                    }
                    .frame(height: max(0, geometry.size.height - consoleHeight))

                    // Console Panel
                    if #available(macOS 15.0, *) {
                        ConsolePanelView(
                            nmeaManager: nmeaManager,
                            consoleHeight: $consoleHeight,
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
                            Label("Start", systemImage: "play.fill")
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

#Preview(traits: .sizeThatFitsLayout) {
    MainView()
        .environment(NMEASimulator())
        .frame(width: 900, height: 550)
}
