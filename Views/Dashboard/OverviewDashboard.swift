//
//  OverviewDashboard.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 20.06.25.
//


import SwiftUI
import MapKit

struct OverviewDashboard: View {
    
    @Environment(NMEASimulator.self) private var nmeaManager

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack {
                    VStack() {

                            // MARK: - Cluster Cards (Top Left)
                        ZStack {
                            DashboardMetricsCard(nmeaManager: nmeaManager,color: .purple)
                            BoatMapPreview(nmeaManager: nmeaManager)
                                .padding(UIConstants.spacing)
                        }

                            // MARK: - Cluster Cards (Top Left)
                        DashboardMetricsCard(nmeaManager: nmeaManager,color: .pink)


                    }
                    VStack() {

                            // MARK: - Cluster Cards (Top Left)
                        DashboardMetricsCard(nmeaManager: nmeaManager, color: .blue)

                            // MARK: - Cluster Cards (Top Left)
                        DashboardMetricsCard(nmeaManager: nmeaManager, color: .teal)

                    }
                }


                // MARK: - Center Compass + Wind
                DashboardWindCompassCard()
                    .frame(width: geo.size.width * 0.4, height: geo.size.width * 0.4)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(radius: 20)
                    )
                    .clipShape(Circle())
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }
}

#Preview {
    OverviewDashboard()
        .environment(NMEASimulator())
        .frame(width: UIConstants.halfScreen, height: UIConstants.minAppWindowHeight)
}




