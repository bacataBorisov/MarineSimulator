import SwiftUI
import AppKit

struct DashboardView: View {
    var isVisible: Bool = true

    @Environment(NMEASimulator.self) private var nmeaManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("dashboard.show_left_dock") private var showLeftDock = true
    @AppStorage("dashboard.show_right_inspector") private var showRightInspector = true
    @AppStorage("dashboard.inspector_width") private var storedInspectorWidth: Double = 340
    @AppStorage("console_panel.last_expanded_height") private var lastExpandedConsoleHeight: Double = 220
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220

    private var leftRailWidth: CGFloat { AppChrome.liveControlRailOuterWidth }
    private let inspectorMinWidth: CGFloat = 280
    private let inspectorMaxWidth: CGFloat = 420

    private var consoleHeight: Binding<CGFloat> {
        Binding(
            get: { CGFloat(max(0, storedLogHeight)) },
            set: { storedLogHeight = Double(max(0, $0)) }
        )
    }

    private var inspectorWidth: CGFloat {
        CGFloat(min(max(storedInspectorWidth, Double(inspectorMinWidth)), Double(inspectorMaxWidth)))
    }

    private var panelAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.03)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if isVisible {
                    topBarChrome
                }

                ZStack(alignment: .bottom) {
                    workspaceMap

                    if isVisible {
                        VStack(spacing: 0) {
                            workspaceDocks
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
            .animation(panelAnimation, value: showRightInspector)
            .animation(panelAnimation, value: showLeftDock)
        }
        .onAppear {
            NSLog("[MarineSim] DashboardView.onAppear")
            ConsoleHeightStorage.migrateIfNeeded()
        }
    }

    private var workspaceMap: some View {
        ZStack {
            BoatMapView(
                isActive: isVisible,
                trailingOverlayInset: showRightInspector ? inspectorWidth : 0
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            mapScrim
                .allowsHitTesting(false)
        }
    }

    private var workspaceDocks: some View {
        HStack(spacing: 0) {
            if showLeftDock {
                LeftControlsPanel(nmea: nmeaManager)
                    .frame(width: leftRailWidth)
                    .frame(maxHeight: .infinity)
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
                HStack(spacing: 0) {
                    inspectorResizeHandle

                    ScrollView {
                        TrailingSidePanel()
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .background(Rectangle().fill(.regularMaterial))
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(width: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private var separatorColor: Color {
        colorScheme == .light ? .black.opacity(0.08) : .white.opacity(0.10)
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

    private var inspectorResizeHandle: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let proposed = storedInspectorWidth - Double(value.translation.width)
                        storedInspectorWidth = min(max(proposed, Double(inspectorMinWidth)), Double(inspectorMaxWidth))
                    }
            )
            .accessibilityLabel("Resize instruments panel")
    }

    private var topBarChrome: some View {
        TopControlBar(
            showLeft: $showLeftDock,
            showRight: $showRightInspector,
            showBottom: Binding(
                get: { consoleHeight.wrappedValue > 0 },
                set: { expanded in
                    let apply = {
                        if expanded {
                            consoleHeight.wrappedValue = max(CGFloat(lastExpandedConsoleHeight), 140)
                        } else {
                            if consoleHeight.wrappedValue > 0 {
                                lastExpandedConsoleHeight = Double(max(consoleHeight.wrappedValue, 140))
                            }
                            consoleHeight.wrappedValue = 0
                        }
                    }
                    if let panelAnimation {
                        withAnimation(panelAnimation, apply)
                    } else {
                        apply()
                    }
                }
            )
        )
        .environment(nmeaManager)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(.ultraThinMaterial))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
        }
    }
}
