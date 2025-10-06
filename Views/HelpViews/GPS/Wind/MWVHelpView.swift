import SwiftUI

struct MWVHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x", "Wind angle (0–359°)"),
        ("R/T", "Reference (R = Relative, T = Theoretical)"),
        ("x.x", "Wind speed"),
        ("K/M/N/S", "Wind speed units"),
        ("A/V", "Status (A = Valid, V = Invalid)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MWV – Wind Speed & Angle")
                    .font(.title3.bold())

                Text("Provides the wind angle and wind speed relative to the vessel or true, and the validity of the data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--MWV,x.x,a,x.x,a,A*hh<CR><LF>")
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

                Text("$WIMWV,045,R,10.2,N,A*hh")
                    .font(.system(.body, design: .monospaced))

                Text("↳ 45° relative wind, 10.2 knots, valid data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    MWVHelpView()
        .frame(width: 500, height: 400)
}
