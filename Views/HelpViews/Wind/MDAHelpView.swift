import SwiftUI

struct MDAHelpView: View {
    @State private var showDetails: Bool = false

    let fields: [(String, String)] = [
        ("x.x,I", "Barometric pressure (inches of mercury)"),
        ("x.x,B", "Barometric pressure (bars)"),
        ("x.x,C", "Air temperature (°C)"),
        ("x.x,C", "Water temperature (°C)"),
        ("x.x", "Relative humidity (%)"),
        ("x.x", "Absolute humidity (%)"),
        ("x.x,C", "Dew point (°C)"),
        ("x.x,T", "Wind direction (True, °)"),
        ("x.x,M", "Wind direction (Magnetic, °)"),
        ("x.x,N", "Wind speed (knots)"),
        ("x.x,M", "Wind speed (m/s)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MDA – Meteorological Composite")
                    .font(.title3.bold())

                Text("Transmits barometric pressure, air and water temperature, relative humidity, dew point, and wind data. Unavailable sensor fields are left empty.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("$--MDA,x.x,I,x.x,B,x.x,C,x.x,C,x.x,,x.x,C,x.x,T,x.x,M,x.x,N,x.x,M*hh<CR><LF>")
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

                Text("$IIMDA,29.92,I,1.0132,B,21.5,C,18.0,C,65.0,,14.6,C,230.0,T,225.0,M,12.5,N,6.4,M*hh")
                    .font(.system(.body, design: .monospaced))

                Text("↳ 1013.2 hPa, 21.5°C air, 18.0°C sea, 65.0% RH, 14.6°C dew point, wind 230°T / 12.5 kn")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    MDAHelpView()
        .frame(width: 500, height: 400)
}
