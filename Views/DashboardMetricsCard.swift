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

struct DashboardWindCompassCard: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                AnemometerView(
                    trueWindAngle: nmeaManager.calculatedTWA ?? 0,
                    apparentWindAngle: nmeaManager.calculatedAWA ?? 0
                )
                
                CompassView()
                
            }
            .aspectRatio(contentMode: .fit)
            
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

}

#Preview {
    DashboardWindCompassCard()
    .frame(width: 400, height: 400)
    .environment(NMEASimulator())
    
}
