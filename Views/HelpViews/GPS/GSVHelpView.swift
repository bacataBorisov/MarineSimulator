//
//  GSVHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 1.07.25.
//


import SwiftUI

struct GSVHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x", "Total number of GSV messages in this cycle"),
        ("x", "Message number (1 of n)"),
        ("xx", "Total number of satellites in view"),
        ("xx", "Satellite PRN number"),
        ("xx", "Elevation in degrees (0–90)"),
        ("xxx", "Azimuth in degrees (0–359)"),
        ("xx", "SNR (Signal to Noise Ratio, 0–99 dBHz)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("GSV – Satellites in View")
                    .font(.title3.bold())

                Text("Provides details of satellites that are currently visible, including their ID, elevation, azimuth, and signal strength. Multiple GSV messages may be needed to describe all satellites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--GSV,x,x,xx,xx,xx,xxx,xx,...*hh<CR><LF>")
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

                Text("$GPGSV,2,1,08,01,40,083,41,02,17,273,38,03,28,113,39,04,07,213,33*76")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Message 1 of 2, 8 satellites in view. First 4 satellites listed with ID, elevation, azimuth, and SNR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    GSVHelpView()
        .frame(width: 500, height: 400)
}