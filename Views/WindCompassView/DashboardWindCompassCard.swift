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
    
    let twd: Double?
    let twa: Double?
    let awa: Double?
    let hdg: Double?
    let width: CGFloat
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                AnemometerView(
                    trueWindAngle: twa ?? 0,
                    apparentWindAngle: awa ?? 0,
                    width: width
                )
                CompassView(width: width)

            }

            .frame(width: width, height: width)
            
            HStack(spacing: 16) {
                displayLabel("TWD", value: twd)
                displayLabel("TWA", value: twa)
                displayLabel("AWA", value: awa)
                displayLabel("HDG", value: hdg)
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func displayLabel(_ label: String, value: Double?) -> some View {
        VStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f°", $0) } ?? "--")
                .font(.title2)
                .monospacedDigit()
        }
    }
}

#Preview {
    DashboardWindCompassCard(
        twd: 86,
        twa: 44,
        awa: 26,
        hdg: 145,
        width: 250
    )
    .environment(NMEASimulator())
    
}
