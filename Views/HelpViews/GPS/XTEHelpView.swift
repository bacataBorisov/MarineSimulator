import SwiftUI

struct XTEHelpView: View {

    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("A", "General warning flag: A = valid"),
        ("A", "Signal/fix status: A = valid"),
        ("x.x", "Cross-track error magnitude in NM"),
        ("a", "Direction to steer: L = left, R = right"),
        ("N", "Units: N = nautical miles")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("XTE – Cross-Track Error")
                    .font(.title3.bold())

                Text("Standalone cross-track error sentence. Indicates how far the vessel is off the intended course line and which direction to steer to correct.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--XTE,A,A,x.x,a,N*hh")
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

                Text("$GPXTE,A,A,0.5,R,N*6F")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Valid fix, 0.5 NM off course, steer right to correct.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
