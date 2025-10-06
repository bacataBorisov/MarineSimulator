//
//  HDGHelpView.swift
//  NMEASimulator
//
//  Created by ChatGPT on 20.06.25.
//

import SwiftUI

struct HDGHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Magnetic sensor heading, degrees"),
        ("x.x", "Magnetic deviation, degrees"),
        ("a", "Deviation direction (E = East, W = West)"),
        ("x.x", "Magnetic variation, degrees"),
        ("a", "Variation direction (E = East, W = West)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("HDG – Heading, Deviation & Variation")
                    .font(.title3.bold())

                Text("Heading (magnetic sensor reading), which if corrected for deviation, will produce Magnetic heading, which if offset by variation will provide True heading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--HDG,x.x,x.x,a,x.x,a*hh<CR><LF>")
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

                Text("$HCHDG,123.4,2.5,E,1.2,W*68")
                    .font(.system(.body, design: .monospaced))

                Text("↳ 123.4° magnetic sensor heading, +2.5° deviation east, -1.2° variation west (valid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes:")
                        .font(.subheadline.bold())

                    Text("1. To obtain Magnetic Heading:")
                    Text("   - Add Easterly deviation (E) to Magnetic Sensor Reading")
                    Text("   - Subtract Westerly deviation (W) from Magnetic Sensor Reading")

                    Text("2. To obtain True Heading:")
                    Text("   - Add Easterly variation (E) to Magnetic Heading")
                    Text("   - Subtract Westerly variation (W) from Magnetic Heading")

                    Text("3. Variation and deviation fields shall be null fields if unknown.")
                }
                .font(.caption)
                .padding(.leading, 8)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    HDGHelpView()
        .frame(width: 500, height: 500)
}