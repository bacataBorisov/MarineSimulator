//
//  NMEASimulatorApp.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

import SwiftUI
import SwiftData

@main
struct MarineSimulator: App {
    
// THIS WAS HERE WHEN I CREATED THE PROJECT I WILL KEEP IT FOR NOW IN CASE I NEED SWIFTDATA
//    var sharedModelContainer: ModelContainer = {
//        let schema = Schema([
//            Item.self,
//        ])
//        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//
//        do {
//            return try ModelContainer(for: schema, configurations: [modelConfiguration])
//        } catch {
//            fatalError("Could not create ModelContainer: \(error)")
//        }
//    }()

    @State private var nmeaManager = NMEASimulator()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(nmeaManager)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        //.modelContainer(sharedModelContainer)
    }
}
