//
//  DBTHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//

import SwiftUI

struct DBTHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Depth below transducer in feet"),
        ("f", "Unit of measurement: feet"),
        ("x.x", "Depth below transducer in meters"),
        ("M", "Unit of measurement: meters"),
        ("x.x", "Depth below transducer in fathoms"),
        ("F", "Unit of measurement: fathoms")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DBT – Depth Below Transducer")
                    .font(.title3.bold())

                Text("Reports the depth of the water directly beneath the transducer. It is typically used by echo sounders and may report depth in feet, meters, and fathoms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--DBT,x.x,f,x.x,M,x.x,F*hh<CR><LF>")
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

                Text("$IIDBT,32.1,f,9.8,M,5.3,F*2C")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Depth: 32.1 ft / 9.8 m / 5.3 fathoms – from transducer downward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    DBTHelpView()
        .frame(width: 500, height: 400)
}