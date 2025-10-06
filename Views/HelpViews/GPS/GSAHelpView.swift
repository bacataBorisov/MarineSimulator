import SwiftUI

struct GSAHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("M", "Mode 1: Manual (M) or Automatic (A) selection of fix type"),
        ("3", "Mode 2: Fix type (1 = No fix, 2 = 2D, 3 = 3D)"),
        ("xx", "PRN number of satellite used (1 to 12 fields, empty if not used)"),
        ("x.x", "PDOP – Position Dilution of Precision"),
        ("x.x", "HDOP – Horizontal Dilution of Precision"),
        ("x.x", "VDOP – Vertical Dilution of Precision")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("GSA – DOP and Active Satellites")
                    .font(.title3.bold())

                Text("Provides information about the GNSS receiver operating mode, fix status, the satellites used in the position fix, and the dilution of precision values.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--GSA,M,3,xx,xx,xx,xx,xx,xx,xx,xx,xx,xx,xx,xx,x.x,x.x,x.x*hh<CR><LF>")
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
                                    .frame(width: 60, alignment: .trailing)
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

                Text("$GPGSA,A,3,04,05,09,12,24,25,29,,,,,,1.8,1.0,1.5*33")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Auto mode, 3D fix using satellites 04, 05, 09, 12, 24, 25, 29; PDOP=1.8, HDOP=1.0, VDOP=1.5.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    GSAHelpView()
        .frame(width: 500, height: 400)
}