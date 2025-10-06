//
//  HDTHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 24.06.25.
//

import SwiftUI

struct HDTHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Heading, degrees True"),
        ("T", "True heading indicator")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("HDT – Heading, True")
                    .font(.title3.bold())

                Text("Actual vessel heading in degrees True produced by any device or system producing true heading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--HDT,x.x,T*hh<CR><LF>")
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

                Text("$HCHDT,213.5,T*36")
                    .font(.system(.body, design: .monospaced))

                Text("↳ 213.5° True heading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    HDTHelpView()
        .frame(width: 500, height: 400)
}
