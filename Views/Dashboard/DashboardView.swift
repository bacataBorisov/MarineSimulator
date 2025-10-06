import SwiftUI
import MapKit

enum DashboardTab: String, CaseIterable {
    case overview = "Overview"
    case fullcontrol = "Full Control" //this is just a working heading
    case map = "Map"
    case advanced = "Advanced"
    case system = "System"
}

struct DashboardView: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager
        
    // panel visibility
    @State private var showLeftDock = true
    @State private var showRightInspector = true
    @State private var showConsole = true

    // panel sizes
    @State private var rightWidth: CGFloat = 340
    @State private var bottomHeight: CGFloat = 180
    
    var body: some View {
        ZStack(alignment: .top) {
            BoatMapPreview(nmeaManager: nmeaManager)
                .ignoresSafeArea()
            
            // Top interactive toolbar
            TopControlBar(showLeft: $showLeftDock,
                          showRight: $showRightInspector,
                          showBottom: $showConsole)
                .environment(nmeaManager)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .top)
                .zIndex(10)
        }
    }
}

#Preview {
    DashboardView()
        .environment(NMEASimulator())
        .frame(width: UIConstants.halfScreen, height: UIConstants.minAppWindowHeight)
}
