//
//  GGAHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 1.07.25.
//


import SwiftUI

struct GGAHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("hhmmss.ss", "UTC of position fix"),
        ("llll.ll", "Latitude in degrees and minutes"),
        ("a", "Latitude hemisphere (N = North, S = South)"),
        ("yyyyy.yy", "Longitude in degrees and minutes"),
        ("a", "Longitude hemisphere (E = East, W = West)"),
        ("x", "GPS Quality Indicator (0 = invalid, 1 = GPS fix, 2 = DGPS fix, etc.)"),
        ("xx", "Number of satellites in use (00 to 12)"),
        ("x.x", "Horizontal dilution of precision (HDOP)"),
        ("x.x", "Antenna altitude above mean sea level (in meters)"),
        ("M", "Units of altitude (meters)"),
        ("x.x", "Height of geoid above WGS84 ellipsoid"),
        ("M", "Units of geoid separation (meters)"),
        ("x.x", "Time since last DGPS update (in seconds)"),
        ("xxxx", "DGPS reference station ID")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("GGA – Global Positioning System Fix Data")
                    .font(.title3.bold())

                Text("Provides essential fix data including 3D location and accuracy metrics such as satellite count, altitude, and correction data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--GGA,hhmmss.ss,llll.ll,a,yyyyy.yy,a,x,xx,x.x,x.x,M,x.x,M,x.x,xxxx*hh<CR><LF>")
                    .font(.system(.body, design: .monospaced).bold())

                Button(action: {
                    withAnimation {
                        showDetails.toggle()
                    }
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
                                    .frame(width: 60, alignment: .trailing)
                                    .fontWeight(.semibold)
                                Text(item.1)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.leading, 8)
                    }
                }

                Divider()
                    .padding(.vertical)

                Text("Example:")
                    .font(.subheadline.bold())

                Text("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Fix at 12:35:19 UTC, 48°07.038'N, 11°31.000'E, GPS fix quality 1, 8 satellites, 0.9 HDOP, 545.4m altitude, geoid separation 46.9m.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    GGAHelpView()
        .frame(width: 500, height: 400)
}