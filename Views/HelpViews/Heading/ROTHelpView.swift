//
//  ROTHelpView.swift
//  NMEASimulator
//
//  Created by ChatGPT on 20.06.25.
//

import SwiftUI

struct ROTHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Rate of turn in degrees per minute (\"-\" = bow turns to port)"),
        ("A/V", "Status (A = Valid, V = Invalid)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("ROT – Rate of Turn")
                    .font(.title3.bold())

                Text("Indicates the rate at which the vessel is turning, expressed in degrees per minute. Negative values indicate a turn to port, positive values to starboard.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--ROT,x.x,A*hh<CR><LF>")
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

                Text("$HCROT,-3.5,A*32")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Turning left (port) at 3.5°/min – Data valid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    ROTHelpView()
        .frame(width: 500, height: 400)
}