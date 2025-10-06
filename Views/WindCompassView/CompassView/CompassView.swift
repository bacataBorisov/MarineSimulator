import SwiftUI

struct CompassView: View {
    @Environment(NMEASimulator.self) private var nmeaManager
    
    let markers = GaugeMarkerCompass.labelSet()
    
    @State private var displayedHeading: Double = 0.0
    @State private var animationDelta: Double = 0.0
    @State private var hasValidHeading: Bool = false
    
    @AppStorage("lastKnownHeading") private var lastKnownHeading: Double = 0.0
    @AppStorage("compassShouldAnimate") private var shouldAnimate: Bool = false
    
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
                        CompassLabelView(marker: marker, size: width/1.33)
                            .frame(width: width, height: width)
                            .transition(.identity) // 👈 prevents any fade or slide animation
                            .animation(nil, value: animationDelta) // 👈 disables animation for label updates
                        
                    }
                }
                .rotationEffect(.degrees(-animationDelta))
                .animation(shouldAnimate ? .easeInOut(duration: 1) : .none, value: animationDelta)
                
                // Yellow Indicator
                Text("▼")
                    .font(.system(size: width / 8, weight: .bold))
                    .position(x: width / 2, y: width / 2)
                    .offset(y: -width / 2)
                    .foregroundColor(.yellow)
                    .scaleEffect(x: 0.82, y: 0.82)

            
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if !hasValidHeading {
                displayedHeading = lastKnownHeading
                animationDelta = lastKnownHeading
                hasValidHeading = true
                shouldAnimate = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    shouldAnimate = true
                }
            }
        }
        .onDisappear {
            lastKnownHeading = displayedHeading
        }
        .onChange(of: nmeaManager.heading.value) { _, newValue in
            guard let newValue = newValue else {
                hasValidHeading = false
                return
            }
            updateCompassRotation(to: newValue)
        }
    }
    
    private func updateCompassRotation(to newHeading: Double) {
        if !hasValidHeading {
            displayedHeading = newHeading
            animationDelta = newHeading
            hasValidHeading = true
        } else {
            let shortestDelta = calculateShortestRotation(from: displayedHeading, to: newHeading)
            animationDelta += shortestDelta
            displayedHeading = newHeading
        }
    }
}

// MARK: - Preview
#Preview {
    CompassView()
        .frame(width: 400, height: 400)
        .environment(NMEASimulator())
}


