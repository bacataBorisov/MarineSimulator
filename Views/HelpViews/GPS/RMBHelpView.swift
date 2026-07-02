import SwiftUI

struct RMBHelpView: View {

    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("A", "Status: A = valid, V = receiver warning"),
        ("x.x", "Cross-track error in nautical miles"),
        ("a", "Direction to steer: L = left, R = right"),
        ("c--c", "Origin waypoint ID"),
        ("c--c", "Destination waypoint ID"),
        ("llll.ll,a", "Destination latitude and N/S"),
        ("yyyyy.yy,a", "Destination longitude and E/W"),
        ("x.x", "Range to destination in nautical miles"),
        ("x.x", "Bearing to destination, degrees true"),
        ("x.x", "Closing velocity (VMC) in knots"),
        ("A", "Arrival status: A = arrived, V = not arrived")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("RMB – Recommended Minimum Navigation")
                    .font(.title3.bold())

                Text("Provides cross-track error, range, bearing, and closing velocity to an active destination waypoint. Sent alongside RMC when waypoint navigation is active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--RMB,A,x.x,a,c--c,c--c,llll.ll,a,yyyyy.yy,a,x.x,x.x,x.x,A*hh")
                    .font(.system(.body, design: .monospaced).bold())

                Button(action: {
                    withAnimation { showDetails.toggle() }
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

                Divider().padding(.vertical)

                Text("Example:")
                    .font(.subheadline.bold())

                Text("$GPRMB,A,0.5,R,WP0,WP1,4830.00,N,00930.00,E,2.3,270.0,5.2,V*1A")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Valid, 0.5 NM cross-track error (steer right), navigating from WP0 to WP1 at 48°30'N 9°30'E, 2.3 NM range, bearing 270°, closing at 5.2 kt, not yet arrived.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
