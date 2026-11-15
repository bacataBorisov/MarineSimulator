import SwiftUI
import AppKit

struct DashboardMapSurface: View {
    var isVisible: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("dashboard.show_right_inspector") private var showRightInspector = true

    private var inspectorWidth: CGFloat { AppChrome.liveControlRailOuterWidth }

    var body: some View {
        ZStack {
            BoatMapView(
                isActive: isVisible,
                trailingOverlayInset: showRightInspector ? inspectorWidth : 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            mapScrim
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapScrim: some View {
        let topOpacity = colorScheme == .light ? 0.06 : 0.16
        let bottomOpacity = colorScheme == .light ? 0.02 : 0.03

        return LinearGradient(
            colors: [
                Color.black.opacity(topOpacity),
                .clear,
                Color.black.opacity(bottomOpacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct DashboardDocksOverlay: View {
    @Bindable var nmeaManager: NMEASimulator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("dashboard.show_left_dock") private var showLeftDock = true
    @AppStorage("dashboard.show_right_inspector") private var showRightInspector = true

    /// Bumped after sleep, a long background, or a long foreground soak so docks remount like a tab swap.
    @State private var dockGeneration = 0
    @State private var resignedActiveAt: Date?

    /// Tab-swap equivalent while staying on the dashboard. `.common` is unsafe with MapKit.
    private static let dockSoakRefresh = Timer.publish(every: 15 * 60, on: .main, in: .default).autoconnect()

    private var leftRailWidth: CGFloat { AppChrome.liveControlRailOuterWidth }
    private var inspectorWidth: CGFloat { AppChrome.liveControlRailOuterWidth }

    private var panelAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.03)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showLeftDock {
                LeftControlsPanel(nmea: nmeaManager)
                    .frame(width: leftRailWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .background(Rectangle().fill(.regularMaterial))
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(separatorColor)
                            .frame(width: 1)
                    }
            }

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            if showRightInspector {
                ScrollView {
                    TrailingSidePanel()
                }
                .scrollIndicators(.hidden)
                .frame(width: inspectorWidth)
                .frame(maxHeight: .infinity)
                .clipped()
                .background(Rectangle().fill(.regularMaterial))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(width: 1)
                }
            }
        }
        .id(dockGeneration)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .animation(panelAnimation, value: showRightInspector)
        .animation(panelAnimation, value: showLeftDock)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            resignedActiveAt = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            remountDocksIfStale(minimumAbsence: 120)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            remountDocksIfStale(minimumAbsence: 0)
        }
        .onReceive(Self.dockSoakRefresh) { _ in
            dockGeneration &+= 1
        }
    }

    /// Remount docks after sleep, a long background, or the 15 min soak timer.
    private func remountDocksIfStale(minimumAbsence: TimeInterval) {
        let absence = resignedActiveAt.map { Date().timeIntervalSince($0) }
        resignedActiveAt = nil
        if minimumAbsence <= 0 || (absence ?? 0) >= minimumAbsence {
            dockGeneration &+= 1
        }
    }

    private var separatorColor: Color {
        colorScheme == .light ? .black.opacity(0.08) : .white.opacity(0.10)
    }
}

struct DashboardView: View {
    var isVisible: Bool = true
    @Bindable var nmeaManager: NMEASimulator
    @AppStorage("console_panel.last_expanded_height") private var lastExpandedConsoleHeight: Double = 220
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    private var consoleHeight: Binding<CGFloat> {
        Binding(
            get: { CGFloat(max(0, storedLogHeight)) },
            set: { storedLogHeight = Double(max(0, $0)) }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                DashboardMapSurface(isVisible: isVisible)

                if isVisible {
                    VStack(spacing: 0) {
                        DashboardDocksOverlay(nmeaManager: nmeaManager)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ConsolePanelView(
                            nmeaManager: nmeaManager,
                            consoleHeight: consoleHeight,
                            geometryHeight: geometry.size.height
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            ConsoleHeightStorage.migrateIfNeeded()
        }
    }
}
