import SwiftUI

struct DashboardView: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    // visibility
    @AppStorage("dashboard.show_left_dock") private var showLeftDock = true
    @AppStorage("dashboard.show_right_inspector") private var showRightInspector = true
    @AppStorage("dashboard.show_console") private var showConsole = true

    @AppStorage("dashboard.console_height") private var storedConsoleHeight: Double = 220

    private let leftRailWidth: CGFloat = 332
    private let rightRailWidth: CGFloat = 340
    private let consoleHeaderHeight: CGFloat = 28

    private var dashboardConsoleHeight: Binding<CGFloat> {
        Binding(
            get: { CGFloat(storedConsoleHeight) },
            set: { storedConsoleHeight = Double($0) }
        )
    }

    private var consoleOverlayInset: CGFloat {
        guard showConsole else { return 0 }
        return CGFloat(storedConsoleHeight) + consoleHeaderHeight
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBarChrome

                ZStack(alignment: .bottom) {
                    ZStack {
                        BoatMapView(trailingOverlayInset: showRightInspector ? rightRailWidth : 0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.16),
                                .clear,
                                Color.black.opacity(showConsole ? 0.12 : 0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    HStack(spacing: 0) {
                        if showLeftDock {
                            LeftControlsPanel(nmea: nmeaManager)
                                .frame(width: leftRailWidth)
                                .frame(maxHeight: .infinity)
                                .background(Rectangle().fill(.regularMaterial))
                                .overlay(alignment: .trailing) {
                                    Rectangle()
                                        .fill(.white.opacity(0.08))
                                        .frame(width: 1)
                                }
                        }

                        Spacer(minLength: 0)

                        if showRightInspector {
                            ScrollView {
                                TrailingSidePanel()
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: rightRailWidth)
                            .frame(maxHeight: .infinity)
                            .background(Rectangle().fill(.regularMaterial))
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(.white.opacity(0.08))
                                    .frame(width: 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, consoleOverlayInset)
                    .allowsHitTesting(true)
                    .zIndex(1)

                    if #available(macOS 15.0, *), showConsole {
                        ConsolePanelView(
                            nmeaManager: nmeaManager,
                            consoleHeight: dashboardConsoleHeight,
                            geometryHeight: geometry.size.height
                        )
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(.white.opacity(0.10))
                                .frame(height: 1)
                        }
                        .shadow(color: .black.opacity(0.26), radius: 18, y: -2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: showRightInspector)
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: showConsole)
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: showLeftDock)
        }
    }

    private var topBarChrome: some View {
        TopControlBar(
            showLeft: $showLeftDock,
            showRight: $showRightInspector,
            showBottom: $showConsole
        )
        .environment(nmeaManager)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(.ultraThinMaterial))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
    }
}
