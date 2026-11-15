import SwiftUI

struct XDRHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("C,x.x,C,AIRTEMP", "Air temperature in °C (Type C)"),
        ("H,x.x,P,HUMIDITY", "Relative humidity in % (Type H)"),
        ("P,x.x,B,BARO", "Barometric pressure in bars (Type P)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("XDR – Transducer Measurement")
                    .font(.title3.bold())

                Text("Emits generic NMEA 0183 transducer quadruplets (type, value, unit, transducer ID) for whichever atmospheric sensors are active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--XDR,a,x.x,u,c--c,...*hh<CR><LF>")
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
                                    .frame(width: 130, alignment: .trailing)
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

                Text("$IIXDR,C,21.5,C,AIRTEMP,H,65.0,P,HUMIDITY,P,1.0132,B,BARO*hh")
                    .font(.system(.body, design: .monospaced))

                Text("↳ Air temp 21.5°C, relative humidity 65.0%, pressure 1.0132 bar (1013.2 hPa)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    XDRHelpView()
        .frame(width: 500, height: 400)
}
