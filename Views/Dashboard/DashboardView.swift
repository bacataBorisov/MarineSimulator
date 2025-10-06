//
//  DashboardView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 14.06.25.
//


//  DashboardView.swift
//  NMEASimulator

import SwiftUI
import MapKit

struct DashboardView: View {
    @Environment(NMEASimulator.self) private var nmeaManager
    
    var body: some View {
        GeometryReader { geometry in
            
            HStack(alignment: .top, spacing: spacing) {
                
                VStack (alignment: .trailing, spacing: spacing){
                    GroupBox(label: Label("Sailing Instruments", systemImage: "safari")) {
                        DashboardWindCompassCard()
                            
                    }
                    .frame(width: 260, height: 260)
                    GroupBox(label: Label("Metrics", systemImage: "safari")) {
                        DashboardMetricsCard()
                            
                    }
                    .frame(width: 260, height: 260)
                }
                GroupBox(label: Label("Position", systemImage: "map")) {
                    BoatMapPreview(coordinate: CLLocationCoordinate2D(
                        latitude: nmeaManager.gps.latitude,
                        longitude: nmeaManager.gps.longitude
                    ))
                }
            }
            .padding(spacing)
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    DashboardView()
        .environment(NMEASimulator())
        .frame(width: 864, height: 600)
}


