
import SwiftUI

@main
struct MarineSimulator: App {
    @State private var nmeaManager = NMEASimulator()

    init() {
        NSLog("[MarineSim] App.init")
        #if DEBUG
        HangProbe.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainView(nmeaManager: nmeaManager)
                .tint(DesignToken.accentPrimary)
                .environment(nmeaManager)
                .onAppear {
                    SimulatorCommandTarget.current = nmeaManager
                    NSLog("[MarineSim] window onAppear sim=%@", String(describing: ObjectIdentifier(nmeaManager)))
                }
                .frame(minWidth: DesignToken.Window.minimumWidth, minHeight: DesignToken.Window.minimumHeight)
        }
        .defaultSize(width: DesignToken.Window.defaultWidth, height: DesignToken.Window.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            MarineSimulatorCommands()
        }
    }
}
