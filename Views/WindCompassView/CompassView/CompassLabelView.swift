import SwiftUI

struct CompassLabelView: View {
    let marker: GaugeMarkerCompass
    let size: CGFloat
    
    var body: some View {
        VStack {
            Text(marker.label)
                .font(.system(size: size * 0.06, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(0))
                .offset(y: -size * 0.49)
        }
        .rotationEffect(.degrees(marker.degrees))
    }
}
