import SwiftUI

struct GLLHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("llll.ll", "Latitude in degrees and minutes"),
        ("a", "N/S indicator ('N' = North, 'S' = South)"),
        ("yyyyy.yy", "Longitude in degrees and minutes"),
        ("a", "E/W indicator ('E' = East, 'W' = West)"),
        ("hhmmss.ss", "UTC of position fix"),
        ("a", "Status (A = Valid, V = Invalid)"),
        ("a", "Mode indicator (A = Autonomous, D = Differential, E = Estimated, etc.)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("GLL – Geographic Position, Latitude/Longitude")
                    .font(.title3.bold())

                Text("Provides latitude and longitude of the vessel with time and status. This is one of the simplest and most direct location sentences.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--GLL,llll.ll,a,yyyyy.yy,a,hhmmss.ss,a,a*hh<CR><LF>")
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
                                    .frame(width: 80, alignment: .trailing)
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

                Text("$GPGLL,4916.45,N,12311.12,W,225444,A,A*5C")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Position: 49°16.45' N, 123°11.12' W at 22:54:44 UTC, valid fix, autonomous mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    GLLHelpView()
        .frame(width: 500, height: 400)
}