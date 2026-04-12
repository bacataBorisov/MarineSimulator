import SwiftUI
import MapKit

struct DashboardView: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    // visibility
    @AppStorage("dashboard.show_left_dock") private var showLeftDock = true
    @AppStorage("dashboard.show_right_inspector") private var showRightInspector = true
    @AppStorage("dashboard.show_console") private var showConsole = true

    @AppStorage("dashboard.console_height") private var storedConsoleHeight: Double = 220
    @State private var topBarHeight: CGFloat = 168
    private let leftRailWidth: CGFloat = 332
    private let rightRailWidth: CGFloat = 340
    private let topBarMinHeight: CGFloat = 168
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
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    TopControlBar(
                        showLeft: $showLeftDock,
                        showRight: $showRightInspector,
                        showBottom: $showConsole
                    )
                    .environment(nmeaManager)
                    .frame(maxWidth: .infinity, minHeight: topBarMinHeight)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: TopBarHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(height: 1)
                    }

                    ZStack {
                        BoatMapView()
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
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                overlayRail(
                    width: showLeftDock ? leftRailWidth : 0,
                    edge: .leading,
                    isVisible: showLeftDock,
                    bottomInset: consoleOverlayInset
                ) {
                    LeftControlsPanel(nmea: nmeaManager)
                }

                overlayRail(
                    width: showRightInspector ? rightRailWidth : 0,
                    edge: .trailing,
                    isVisible: showRightInspector,
                    bottomInset: consoleOverlayInset
                ) {
                    ScrollView {
                        TrailingSidePanel()
                    }
                    .scrollIndicators(.hidden)
                }

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
            .onPreferenceChange(TopBarHeightPreferenceKey.self) { height in
                topBarHeight = max(topBarMinHeight, height)
            }
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: showRightInspector)
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: showConsole)
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: showLeftDock)
        }
    }

    @ViewBuilder
    private func overlayRail<Content: View>(
        width: CGFloat,
        edge: HorizontalEdge,
        isVisible: Bool,
        bottomInset: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            if edge == .trailing {
                Spacer(minLength: 0)
            }

            content()
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(
                    Rectangle()
                        .fill(.regularMaterial)
                )
                .opacity(isVisible ? 1 : 0)
                .clipped()
                .allowsHitTesting(isVisible)
                .overlay(alignment: edge == .leading ? .trailing : .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1)
                }

            if edge == .leading {
                Spacer(minLength: 0)
            }
        }
        .padding(.top, topBarHeight)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .leading : .trailing)
    }
}

private struct TopBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 168

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
