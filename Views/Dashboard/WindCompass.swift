import SwiftUI
import Combine

struct WindCompass: View {
    @Environment(NMEASimulator.self) private var nmea

    @AppStorage("storedTrueWindAngle") private var storedTrueWindAngle: Double = 0.0
    @AppStorage("storedApparentWindAngle") private var storedApparentWindAngle: Double = 0.0
    @AppStorage("anemometerShouldAnimate") private var anemometerShouldAnimate: Bool = false

    @AppStorage("lastKnownHeading") private var lastKnownHeading: Double = 0.0
    @AppStorage("compassShouldAnimate") private var compassShouldAnimate: Bool = false

    @State private var displayedTrueWindAngle: Double = 0.0
    @State private var displayedApparentWindAngle: Double = 0.0

    @State private var displayedHeading: Double = 0.0
    @State private var compassAnimationDelta: Double = 0.0
    @State private var hasValidCompassHeading: Bool = false

    /// Last NMEA-derived key we applied; avoids idle timer work and avoids `onChange(of: String)`.
    @State private var lastAppliedInstrumentKey: String = ""

    /// ~24 Hz poll when not tacking; tack uses `tackInstrumentStepNotification` only.
    private static let idleInstrumentPoll = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    private func instrumentDependencyKey() -> String {
        let m = nmea.heading.value.map { String(format: "%.4f", $0) } ?? "nil"
        let g = nmea.gyroHeading.value.map { String(format: "%.4f", $0) } ?? "nil"
        let t = nmea.calculatedTWA.map { String(format: "%.4f", $0) } ?? "x"
        let a = nmea.calculatedAWA.map { String(format: "%.4f", $0) } ?? "x"
        return "\(m)|\(g)|\(t)|\(a)"
    }

    /// Snap during tack (no stacked `withAnimation`); smooth ease when idle.
    private var windArrowAnimation: Animation? {
        if nmea.isTackInProgress {
            return nil
        }
        if anemometerShouldAnimate {
            return .easeInOut(duration: 1)
        }
        return nil
    }

    private var compassDialAnimation: Animation? {
        if nmea.isTackInProgress {
            return nil
        }
        if compassShouldAnimate {
            return .easeInOut(duration: 1)
        }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            let instrumentWidth = min(geometry.size.width, 320)
            let gaugeWidth = max(instrumentWidth - 8, 220)
            let compassWidth = max(gaugeWidth - 22, 196)

            ZStack {
                ZStack {
                    AnemometerView(
                        displayedTrueWindAngle: $displayedTrueWindAngle,
                        displayedApparentWindAngle: $displayedApparentWindAngle,
                        arrowRotationAnimation: windArrowAnimation
                    )
                    .frame(width: gaugeWidth, height: gaugeWidth)

                    CompassView(
                        displayedHeading: $displayedHeading,
                        animationDelta: $compassAnimationDelta,
                        hasValidHeading: $hasValidCompassHeading,
                        dialRotationAnimation: compassDialAnimation
                    )
                    .frame(width: compassWidth, height: compassWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 296)
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            displayedTrueWindAngle = storedTrueWindAngle
            displayedApparentWindAngle = storedApparentWindAngle
            anemometerShouldAnimate = false
            lastAppliedInstrumentKey = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let twa = nmea.calculatedTWA ?? 0
                let awa = nmea.calculatedAWA ?? 180
                let introAnim = anemometerShouldAnimate ? Animation.easeInOut(duration: 1) : nil
                applyWindDelta($displayedTrueWindAngle, to: twa, animation: introAnim)
                applyWindDelta($displayedApparentWindAngle, to: awa, animation: introAnim)
                anemometerShouldAnimate = true
                lastAppliedInstrumentKey = instrumentDependencyKey()
            }

            if !hasValidCompassHeading {
                displayedHeading = lastKnownHeading
                compassAnimationDelta = lastKnownHeading
                hasValidCompassHeading = true
                compassShouldAnimate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    compassShouldAnimate = true
                }
            }
        }
        .onDisappear {
            lastKnownHeading = displayedHeading
        }
        .onReceive(NotificationCenter.default.publisher(for: NMEASimulator.tackInstrumentStepNotification)) { output in
            guard let sender = output.object as? NMEASimulator, sender === nmea else { return }
            syncInstrumentsFromNMEA()
        }
        .onReceive(Self.idleInstrumentPoll) { _ in
            guard !nmea.isTackInProgress else { return }
            let key = instrumentDependencyKey()
            guard key != lastAppliedInstrumentKey else { return }
            syncInstrumentsFromNMEA()
        }
    }

    private func syncInstrumentsFromNMEA() {
        let twa = nmea.calculatedTWA ?? 0
        let awa = nmea.calculatedAWA ?? 180
        let windAnim: Animation? = nmea.isTackInProgress
            ? nil
            : (anemometerShouldAnimate ? .easeInOut(duration: 1) : nil)
        applyWindDelta($displayedTrueWindAngle, to: twa, animation: windAnim)
        applyWindDelta($displayedApparentWindAngle, to: awa, animation: windAnim)
        storedTrueWindAngle = twa
        storedApparentWindAngle = awa

        let headingValue = nmea.heading.value ?? nmea.gyroHeading.value ?? 0
        applyCompassRotation(to: headingValue)

        lastAppliedInstrumentKey = instrumentDependencyKey()
    }

    private func applyWindDelta(_ value: Binding<Double>, to newAngle: Double, animation: Animation?) {
        let shortestDelta = calculateShortestRotation(from: value.wrappedValue, to: newAngle)
        guard let animation else {
            value.wrappedValue += shortestDelta
            return
        }
        withAnimation(animation) {
            value.wrappedValue += shortestDelta
        }
    }

    private func applyCompassRotation(to newHeading: Double) {
        if !hasValidCompassHeading {
            displayedHeading = newHeading
            compassAnimationDelta = newHeading
            hasValidCompassHeading = true
        } else {
            let shortestDelta = calculateShortestRotation(from: displayedHeading, to: newHeading)
            let compassAnim: Animation? = nmea.isTackInProgress
                ? nil
                : (compassShouldAnimate ? .easeInOut(duration: 1) : nil)
            if let compassAnim {
                withAnimation(compassAnim) {
                    compassAnimationDelta += shortestDelta
                    displayedHeading = newHeading
                }
            } else {
                compassAnimationDelta += shortestDelta
                displayedHeading = newHeading
            }
        }
    }
}

#Preview {
    WindCompass()
        .frame(width: 300, height: 300)
        .environment(NMEASimulator())
}
