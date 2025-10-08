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
            // set the minimum to be half split screen on macbook pro 16 for now.
            // ideally i want to be 1/4 but not sure how to do it to be visible for now
                .frame(minWidth: (NSScreen.main?.frame.width ?? 1728) / 2,
                       minHeight: 520 + (3 * UIConstants.spacing))

        }
        //.modelContainer(sharedModelContainer)
    }
}
