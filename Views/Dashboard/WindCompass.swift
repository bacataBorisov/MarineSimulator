import SwiftUI
import Combine
import AppKit

struct WindCompass: View {
    var isActive: Bool = true

    @Environment(NMEASimulator.self) private var nmea
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var lastInstrumentCommitAt: CFAbsoluteTime = 0

    /// Match the 10 Hz display clock. `.common` fires during MapKit tracking and can wedge the main thread.
    private static let idleInstrumentPollInterval: TimeInterval = 0.1
    private static let idleInstrumentPoll = Timer.publish(every: idleInstrumentPollInterval, on: .main, in: .default).autoconnect()
    /// One 1 s ease at a time. Retargeting at 10 Hz is what stacked overnight.
    private static let instrumentCommitInterval: TimeInterval = 0.85
    private static let largeInstrumentStep = 2.5

    private func instrumentDependencyKey() -> String {
        let m = nmea.heading.value.map { String(format: "%.4f", $0) } ?? "nil"
        let g = nmea.gyroHeading.value.map { String(format: "%.4f", $0) } ?? "nil"
        let c = String(format: "%.4f", nmea.gpsData.courseOverGround)
        let t = nmea.calculatedTWA.map { String(format: "%.4f", $0) } ?? "x"
        let a = nmea.calculatedAWA.map { String(format: "%.4f", $0) } ?? "x"
        return "\(m)|\(g)|\(c)|\(t)|\(a)"
    }

    private var liveInstrumentAnimation: Animation? {
        if nmea.isTackInProgress {
            return .linear(duration: Self.idleInstrumentPollInterval)
        }
        if anemometerShouldAnimate || compassShouldAnimate {
            return .easeInOut(duration: 1)
        }
        return nil
    }

    private var windArrowAnimation: Animation? { liveInstrumentAnimation }
    private var compassDialAnimation: Animation? { liveInstrumentAnimation }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let gaugeWidth = max(side - 8, 120)
            let compassWidth = max(gaugeWidth * 0.90, 108)

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wind and compass dial")
            .accessibilityValue(
                "Heading \(Int(normalizeAngle(displayedHeading).rounded()))°, "
                + "True wind angle \(Int(normalizeAngle(displayedTrueWindAngle).rounded()))°, "
                + "Apparent wind angle \(Int(normalizeAngle(displayedApparentWindAngle).rounded()))°"
            )
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            let twa = normalizeAngle(nmea.calculatedTWA ?? storedTrueWindAngle)
            let awa = normalizeAngle(nmea.calculatedAWA ?? storedApparentWindAngle)
            var snapTransaction = Transaction()
            snapTransaction.disablesAnimations = true
            withTransaction(snapTransaction) {
                anemometerShouldAnimate = false
                displayedTrueWindAngle = twa
                displayedApparentWindAngle = awa
                if !hasValidCompassHeading {
                    let initialHeading = normalizeAngle(lastKnownHeading)
                    displayedHeading = initialHeading
                    compassAnimationDelta = initialHeading
                    hasValidCompassHeading = true
                    compassShouldAnimate = false
                }
            }
            lastAppliedInstrumentKey = instrumentDependencyKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                anemometerShouldAnimate = true
                compassShouldAnimate = true
            }
        }
        .onDisappear {
            lastKnownHeading = displayedHeading
            storedTrueWindAngle = displayedTrueWindAngle
            storedApparentWindAngle = displayedApparentWindAngle
        }
        .onChange(of: nmea.gyroHeading.value) { _, _ in
            guard nmea.isTackInProgress else { return }
            syncInstrumentsFromNMEA(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NMEASimulator.tackInstrumentStepNotification)) { output in
            guard let sender = output.object as? NMEASimulator, sender === nmea else { return }
            syncInstrumentsFromNMEA(force: true)
        }
        .onReceive(Self.idleInstrumentPoll) { _ in
            guard isActive, NSApp.isActive else { return }
            guard scenePhase == .active else { return }
            if nmea.isTackInProgress {
                syncInstrumentsFromNMEA(force: true)
                return
            }
            let key = instrumentDependencyKey()
            guard key != lastAppliedInstrumentKey else { return }
            syncInstrumentsFromNMEA()
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            snapInstrumentsAfterWake()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            snapInstrumentsAfterWake()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            snapInstrumentsAfterWake()
        }
    }

    /// Lid-open / page-remount equivalent: drop the 1 s ease and fold a night of accumulated dial degrees.
    private func snapInstrumentsAfterWake() {
        lastAppliedInstrumentKey = ""
        anemometerShouldAnimate = false
        compassShouldAnimate = false
        syncInstrumentsFromNMEA(force: true)
        foldCompassDeltaIfNeeded()
        anemometerShouldAnimate = true
        compassShouldAnimate = true
    }

    private func syncInstrumentsFromNMEA(force: Bool = false) {
        let liveWind = nmea.liveManeuverWindAngles()
        let twa = liveWind?.trueAngle ?? nmea.calculatedTWA ?? 0
        let awa = liveWind?.apparentAngle ?? nmea.calculatedAWA ?? 180
        let headingValue: Double = {
            if nmea.sensorToggles.hasGyro, let gyro = nmea.gyroHeading.value {
                return gyro
            }
            if nmea.sensorToggles.hasCompass, let mag = nmea.heading.value {
                return mag
            }
            return nmea.gpsData.courseOverGround
        }()

        let windStep = max(
            abs(calculateShortestRotation(from: displayedTrueWindAngle, to: twa)),
            abs(calculateShortestRotation(from: displayedApparentWindAngle, to: awa))
        )
        let headingStep = hasValidCompassHeading
            ? abs(calculateShortestRotation(from: displayedHeading, to: headingValue))
            : Self.largeInstrumentStep
        let now = CFAbsoluteTimeGetCurrent()
        let due = force
            || nmea.isTackInProgress
            || now - lastInstrumentCommitAt >= Self.instrumentCommitInterval
            || windStep >= Self.largeInstrumentStep
            || headingStep >= Self.largeInstrumentStep
        guard due else { return }

        lastInstrumentCommitAt = now
        applyWindDelta($displayedTrueWindAngle, to: twa)
        applyWindDelta($displayedApparentWindAngle, to: awa)
        foldWindAnglesIfNeeded()
        applyCompassRotation(to: headingValue)
        lastAppliedInstrumentKey = instrumentDependencyKey()
    }

    private func applyWindDelta(_ value: Binding<Double>, to newAngle: Double) {
        let shortestDelta = calculateShortestRotation(from: value.wrappedValue, to: newAngle)
        value.wrappedValue += shortestDelta
    }

    private func foldWindAnglesIfNeeded() {
        guard abs(displayedTrueWindAngle) > 360 || abs(displayedApparentWindAngle) > 360 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if abs(displayedTrueWindAngle) > 360 {
                displayedTrueWindAngle = normalizeAngle(displayedTrueWindAngle)
            }
            if abs(displayedApparentWindAngle) > 360 {
                displayedApparentWindAngle = normalizeAngle(displayedApparentWindAngle)
            }
        }
    }

    private func applyCompassRotation(to newHeading: Double) {
        if !hasValidCompassHeading {
            displayedHeading = newHeading
            compassAnimationDelta = newHeading
            hasValidCompassHeading = true
        } else {
            let shortestDelta = calculateShortestRotation(from: displayedHeading, to: newHeading)
            compassAnimationDelta += shortestDelta
            displayedHeading = newHeading
            foldCompassDeltaIfNeeded()
        }
    }

    /// `rotationEffect` uses the raw delta. A day of 10 Hz heading noise can push it
    /// to tens of thousands of degrees; fold without animation so the next slider
    /// move is not a 1 s ease across a huge stacked rotation.
    private func foldCompassDeltaIfNeeded() {
        guard abs(compassAnimationDelta) > 360 else { return }
        var folded = compassAnimationDelta.truncatingRemainder(dividingBy: 360)
        if folded < 0 { folded += 360 }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            compassAnimationDelta = folded
        }
    }
}

#Preview {
    WindCompass()
        .frame(width: 300, height: 300)
        .environment(NMEASimulator())
}
