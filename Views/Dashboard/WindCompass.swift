import SwiftUI

struct WindCompass: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    var body: some View {
        ZStack {
            AnemometerView(
                trueWindAngle: nmeaManager.calculatedTWA ?? 0,
                apparentWindAngle: nmeaManager.calculatedAWA ?? 180
            )
            .frame(width: 285, height: 285) // slightly smaller inner view

            CompassView()
                .frame(width: 255, height: 255)
        }
        .frame(width: 300, height: 300) // fixed size container
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 6)
    }
}

#Preview {
    WindCompass()
        .frame(width: 300, height: 300)
        .environment(NMEASimulator())
}
