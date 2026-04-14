import SwiftUI

struct CompassView: View {

    let markers = GaugeMarkerCompass.labelSet()

    @Binding var displayedHeading: Double
    @Binding var animationDelta: Double
    @Binding var hasValidHeading: Bool
    /// Dial rotation animation (`nil` = jump).
    var dialRotationAnimation: Animation?

    var body: some View {

        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Compass Circle
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [Color("dial_gauge_start"), Color("dial_gauge_end")]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: width / 12
                    )
                    .padding(width / 20)
                    .scaleEffect(x: 0.82, y: 0.82)

                // Compass Labels (recentered manually)
                ForEach(markers) { marker in
                    CompassLabelView(marker: marker, size: width / 1.33)
                        .frame(width: width, height: width)
                        .transition(.identity)
                        .animation(nil, value: animationDelta)
                }
            }
            .rotationEffect(.degrees(-animationDelta))
            .animation(dialRotationAnimation, value: animationDelta)

            // Yellow Indicator
            Text("▼")
                .font(.system(size: width / 8, weight: .bold))
                .position(x: width / 2, y: width / 2)
                .offset(y: -width / 2)
                .foregroundColor(.yellow)
                .scaleEffect(x: 0.82, y: 0.82)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Preview
#Preview {
    @Previewable @State var displayedHeading = 0.0
    @Previewable @State var animationDelta = 0.0
    @Previewable @State var hasValid = true
    CompassView(
        displayedHeading: $displayedHeading,
        animationDelta: $animationDelta,
        hasValidHeading: $hasValid,
        dialRotationAnimation: .easeInOut(duration: 1)
    )
    .frame(width: 400, height: 400)
}
