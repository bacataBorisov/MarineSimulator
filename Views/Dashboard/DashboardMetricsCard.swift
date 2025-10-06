//
//  DashboardWindCompassCard.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 15.06.25.
//


//
//  DashboardWindCard.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 14.06.25.
//


// DashboardWindCard.swift
// A compact macOS-compatible SwiftUI view for visualizing live wind angles

import SwiftUI

struct DashboardMetricsCard: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager
    
    var body: some View {
        ZStack() {
            HydroMetricsView()
            
        }
        .aspectRatio(contentMode: .fit)
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}

#Preview {
    DashboardMetricsCard()
        .frame(width: 300, height: 300)
        .environment(NMEASimulator())
    
}
