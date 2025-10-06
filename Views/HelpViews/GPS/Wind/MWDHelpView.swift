import SwiftUI

struct MWDHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Wind direction (True), 0–359°"),
        ("T", "True direction indicator"),
        ("x.x", "Wind direction (Magnetic), 0–359°"),
        ("M", "Magnetic direction indicator"),
        ("x.x", "Wind speed in knots"),
        ("N", "Knots unit indicator"),
        ("x.x", "Wind speed in m/s"),
        ("M", "Meters/second unit indicator"),
        ("A/V", "Status (A = Valid, V = Invalid)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MWD – Wind Direction & Speed")
                    .font(.title3.bold())

                Text("The direction from which the wind blows across the earth’s surface, with respect to north, and the speed of the wind.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--MWD,x.x,T,x.x,M,x.x,N,x.x,M*hh<CR><LF>")
                    .font(.system(.body, design: .monospaced).bold())

                // Custom expandable section
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

                Text("$WIMWD,230.0,T,215.0,M,12.5,N,6.4,M*hh")
                    .font(.system(.body, design: .monospaced))

                Text("↳ 230° True, 215° Magnetic, 12.5 knots, 6.4 m/s (Valid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    MWDHelpView()
        .frame(width: 500, height: 400)
}
