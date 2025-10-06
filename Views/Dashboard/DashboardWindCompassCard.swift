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
        GeometryReader { geo in
            let minSize = min(geo.size.width, geo.size.height)

            VStack {
                ZStack {
                    AnemometerView(
                        trueWindAngle: nmeaManager.calculatedTWA ?? 0,
                        apparentWindAngle: nmeaManager.calculatedAWA ?? 180
                    )
                    .frame(width: minSize * 0.95, height: minSize * 0.95)

                    CompassView()
                        .frame(width: minSize * 0.85, height: minSize * 0.85)
                }
                .frame(width: minSize, height: minSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 6)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    DashboardWindCompassCard()
    .frame(width: 400, height: 400)
    .environment(NMEASimulator())
    
}
