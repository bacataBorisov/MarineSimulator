import SwiftUI
import MapKit

struct DashboardView: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    // visibility
    @State private var showLeftDock = true
    @State private var showRightInspector = true
    @State private var showConsole = true

    // sizes
    @State private var leftWidth: CGFloat = 320
    @State private var rightWidth: CGFloat = 300
    @State private var bottomHeight: CGFloat = 180

    // assume your top bar is ~48pt tall (tweak if needed)
    private let topBarHeight: CGFloat = 48
    private let topBarSpacing: CGFloat = 8

    var body: some View {
        ZStack(alignment: .top) {
            // main map
            BoatMapView()

            // TOP BAR
            TopControlBar(
                showLeft: $showLeftDock,
                showRight: $showRightInspector,
                showBottom: $showConsole
            )
            .environment(nmeaManager)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .top)
            .zIndex(10)
            
            // LEFT: Full Control (your sliders/toggles)
            LeadingSidePanel(
                edge: .leading,
                isVisible: $showLeftDock,
                topOffset: topBarHeight + topBarSpacing
            ) {
                LeftControlsPanel(nmea: nmeaManager)
            }
            // RIGHT SIDEBAR — now padded below the top bar
            if showRightInspector {
                HStack {
                    Spacer()
                    TrailingSidePanel()
                        .frame(width: rightWidth)
                        .padding(.top, topBarHeight + topBarSpacing) // 👈 keeps it under the bar
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(9)
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showRightInspector)
    }
}
