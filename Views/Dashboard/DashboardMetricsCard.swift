//
//  DashboardWindCompassCard.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 15.06.25.
//
import SwiftUI

struct DashboardMetricsCard: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    var title: String?
    var systemImage: String?
    var color: Color = .orange
    
    var body: some View {
        ZStack() {
            // Background card
            Rectangle() // Set radius if you want curved edges
                .fill(color.opacity(0.2)) // Or use Color or Gradient
        }
        //.clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    DashboardMetricsCard(nmeaManager: NMEASimulator())
        .frame(width: 300, height: 300)
        .environment(NMEASimulator())
    
}
