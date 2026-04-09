import SwiftUI

struct WindCompass: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    var body: some View {
        GeometryReader { geometry in
            let instrumentWidth = min(geometry.size.width, 320)
            let gaugeWidth = max(instrumentWidth - 8, 220)
            let compassWidth = max(gaugeWidth - 22, 196)

            ZStack {
                ZStack {
                    AnemometerView(
                        trueWindAngle: nmeaManager.calculatedTWA ?? 0,
                        apparentWindAngle: nmeaManager.calculatedAWA ?? 180
                    )
                    .frame(width: gaugeWidth, height: gaugeWidth)

                    CompassView()
                        .frame(width: compassWidth, height: compassWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 296)
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    WindCompass()
        .frame(width: 300, height: 300)
        .environment(NMEASimulator())
}
