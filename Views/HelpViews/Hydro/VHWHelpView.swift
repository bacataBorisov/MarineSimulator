//
//  VHWHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//


import SwiftUI

struct VHWHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "True heading (degrees)"),
        ("T", "Indicator for True"),
        ("x.x", "Magnetic heading (degrees)"),
        ("M", "Indicator for Magnetic"),
        ("x.x", "Speed through water (knots)"),
        ("N", "Indicator for Knots"),
        ("x.x", "Speed through water (km/h)"),
        ("K", "Indicator for Kilometers per hour")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("VHW – Water Speed and Heading")
                    .font(.title3.bold())

                Text("Reports the vessel's heading and speed through water, including both magnetic and true heading, as well as speed in knots and kilometers per hour.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--VHW,x.x,T,x.x,M,x.x,N,x.x,K*hh<CR><LF>")
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
                                    .frame(width: 50, alignment: .trailing)
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

                Text("$IIVHW,357.0,T,355.6,M,7.5,N,13.9,K*7B")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Heading: 357° True, 355.6° Magnetic; Speed: 7.5 kn / 13.9 km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    VHWHelpView()
        .frame(width: 500, height: 400)
}
