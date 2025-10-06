//
//  VLWHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//

import SwiftUI

struct VLWHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Total cumulative distance traveled (nautical miles)"),
        ("N", "Unit of measurement: nautical miles"),
        ("x.x", "Distance traveled since reset (nautical miles)"),
        ("N", "Unit of measurement: nautical miles")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("VLW – Distance Traveled Through Water")
                    .font(.title3.bold())

                Text("Reports the total and trip (resettable) distance traveled through water in nautical miles. Typically used by a speed log or trip counter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--VLW,x.x,N,x.x,N*hh<CR><LF>")
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

                Text("$IIVLW,1234.5,N,18.7,N*68")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Total: 1234.5 nm, Trip: 18.7 nm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    VLWHelpView()
        .frame(width: 500, height: 400)
}