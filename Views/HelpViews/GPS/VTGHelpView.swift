//
//  VTGHelpView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 1.07.25.
//


import SwiftUI

struct VTGHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Course over ground, degrees True"),
        ("T", "True course indicator"),
        ("x.x", "Course over ground, degrees Magnetic (optional)"),
        ("M", "Magnetic course indicator"),
        ("x.x", "Speed over ground, knots"),
        ("N", "Knots indicator"),
        ("x.x", "Speed over ground, km/h"),
        ("K", "Kilometers per hour indicator"),
        ("a", "Mode indicator (A = Autonomous, D = Differential, E = Estimated, etc.)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("VTG – Course Over Ground and Ground Speed")
                    .font(.title3.bold())

                Text("Provides the course made good and speed relative to the ground. Both true and magnetic course may be included, along with speed in knots and kilometers per hour.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--VTG,x.x,T,x.x,M,x.x,N,x.x,K,a*hh<CR><LF>")
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

                Text("$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K,A*23")
                    .font(.system(.body, design: .monospaced))

                Text("↳ True course: 54.7°, magnetic course: 34.4°, speed: 5.5 knots (10.2 km/h), mode: Autonomous.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    VTGHelpView()
        .frame(width: 500, height: 400)
}