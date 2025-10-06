//
//  FullControlView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 22.06.25.
//

import SwiftUI

struct FullControlView: View {
    @Environment(NMEASimulator.self) private var nmeaSimulator
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                SectionHeader(title: "Wind")
                
                //WindRawControlView(nmeaManager: nmeaManager)
                
                SectionHeader(title: "GPS")
                EmptyView()
                //GPSRawControlView(nmeaManager: nmeaManager)

                SectionHeader(title: "Hydro")
                EmptyView()

                //HydroRawControlView(nmeaManager: nmeaManager)

                SectionHeader(title: "Compass")
                HeadingConfig(nmeaManager: nmeaManager)
                

                SectionHeader(title: "System")
                EmptyView()

                //SystemStatusView(nmeaManager: nmeaManager)
            }
            .padding()
        }
        .navigationTitle("Full Control")
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }
}

#Preview {
    FullControlView(nmeaManager: NMEASimulator())
        .environment(NMEASimulator())
        .frame(width: halfScreen, height: minAppWindowHeight)
}
