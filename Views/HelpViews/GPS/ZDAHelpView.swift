import SwiftUI

struct ZDAHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("hhmmss.ss", "UTC Time (hours, minutes, seconds)"),
        ("dd", "Day of month (01–31)"),
        ("mm", "Month (01–12)"),
        ("yyyy", "Year"),
        ("xx", "Local zone hours offset from UTC"),
        ("yy", "Local zone minutes offset from UTC")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("ZDA – Time and Date")
                    .font(.title3.bold())

                Text("Provides Coordinated Universal Time (UTC), date, and local time zone offset. Useful when synchronizing onboard clocks or displaying accurate date/time info.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--ZDA,hhmmss.ss,dd,mm,yyyy,xx,yy*hh<CR><LF>")
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
                                    .frame(width: 90, alignment: .trailing)
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

                Text("$GPZDA,172809.00,12,07,2025,00,00*67")
                    .font(.system(.body, design: .monospaced))

                Text("↳ UTC time 17:28:09.00 on July 12, 2025. Time zone offset 00:00 (UTC).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    ZDAHelpView()
        .frame(width: 500, height: 400)
}