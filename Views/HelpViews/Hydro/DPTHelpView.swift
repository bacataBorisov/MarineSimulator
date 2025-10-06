//
//  DPTHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//

import SwiftUI

struct DPTHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Depth below the transducer, in meters"),
        ("x.x", "Offset from transducer (positive = distance from transducer to waterline, negative = distance to keel)"),
        ("x.x", "Maximum range scale in use (optional)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DPT – Depth of Water")
                    .font(.title3.bold())

                Text("Indicates the depth below the transducer and optionally includes the offset to waterline or keel, and the echo sounder's current maximum range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--DPT,x.x,x.x,x.x*hh<CR><LF>")
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

                Text("$IIDPT,10.5,0.3,20.0*6B")
                    .font(.system(.body, design: .monospaced))

                Text("↳ 10.5 meters below transducer, with 0.3 m offset to waterline, and 20 m range scale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    DPTHelpView()
        .frame(width: 500, height: 400)
}