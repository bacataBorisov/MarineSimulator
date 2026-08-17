
import SwiftUI
import SwiftData

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
                .environment(nmeaManager)
                .onAppear {
                    SimulatorCommandTarget.current = nmeaManager
                    NSLog("[MarineSim] window onAppear sim=%@", String(describing: ObjectIdentifier(nmeaManager)))
                }
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            MarineSimulatorCommands()
        }
    }
}
