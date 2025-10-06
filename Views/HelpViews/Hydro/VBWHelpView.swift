//
//  VBWHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//

import SwiftUI

struct VBWHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Longitudinal water speed (knots)"),
        ("x.x", "Transverse water speed (knots)"),
        ("A/V", "Status: A = Valid, V = Invalid (water speed)"),
        ("x.x", "Longitudinal ground speed (knots)"),
        ("x.x", "Transverse ground speed (knots)"),
        ("A/V", "Status: A = Valid, V = Invalid (ground speed)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("VBW – Dual Ground/Water Speed")
                    .font(.title3.bold())

                Text("Reports vessel's speed relative to both the water and the ground, separated into longitudinal and transverse components. Used for more advanced speed sensors.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--VBW,x.x,x.x,A,x.x,x.x,A*hh<CR><LF>")
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

                Text("$IIVBW,5.4,0.2,A,5.6,0.1,A*3F")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Water Speed: 5.4 kn fwd / 0.2 kn sideways (valid); Ground Speed: 5.6 kn fwd / 0.1 kn sideways (valid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    VBWHelpView()
        .frame(width: 500, height: 400)
}
