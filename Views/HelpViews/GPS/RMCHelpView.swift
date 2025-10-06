//
//  RMCHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 1.07.25.
//

import SwiftUI

struct RMCHelpView: View {
    
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("hhmmss.ss", "UTC of position fix"),
        ("A", "Status: A = valid, V = navigation receiver warning"),
        ("llll.ll,a", "Latitude (degrees, minutes) and N/S hemisphere"),
        ("yyyyy.yy,a", "Longitude (degrees, minutes) and E/W hemisphere"),
        ("x.x", "Speed over ground in knots"),
        ("x.x", "Course over ground in degrees True"),
        ("ddmmyy", "Date: day, month, year"),
        ("x.x,a", "Magnetic variation and direction (E = subtracts from course, W = adds)"),
        ("a", "Mode Indicator: A=Autonomous, D=Differential, E=Estimated, M=Manual, S=Simulator, N=Invalid")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("RMC – Recommended Minimum Navigation Info")
                    .font(.title3.bold())

                Text("Provides time, date, position, course, and speed data from a GNSS navigation receiver. Sent at intervals ≤ 2 seconds and always accompanied by RMB if a destination waypoint is active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--RMC,hhmmss.ss,A,llll.ll,a,yyyyy.yy,a,x.x,x.x,ddmmyy,x.x,a,a*hh")
                    .font(.system(.body, design: .monospaced).bold())

                Button(action: {
                    withAnimation { showDetails.toggle() }
                }) {
                    HStack {
                        Text("Field Breakdown")
                            .foregroundColor(.accentColor)
                            .font(.body.bold())
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)

                if showDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(fields.indices, id: \.self) { index in
                            let item = fields[index]
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.0)
                                    .frame(width: 80, alignment: .trailing)
                                    .fontWeight(.semibold)
                                Text(item.1)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.leading, 8)
                    }
                }

                Divider().padding(.vertical)

                Text("Example:")
                    .font(.subheadline.bold())

                Text("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W,A*6C")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Valid fix at 12:35:19 UTC, position 48°07.038'N 11°31.000'E, 22.4 knots, course 84.4°, March 23, 1994, 3.1° west variation, Autonomous mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
