//
//  DashboardChrome.swift
//  NMEASimulator
//
//  Shared layout and controls for dashboard rails (left live controls, right inspector).
//

import SwiftUI

// MARK: - Circular heading / wind direction (0° ≡ 360°)

private func wrappedCircularSetpoint(_ raw: Double, range: ClosedRange<Double>) -> Double {
    normalizeAngle(raw).clamped(to: range)
}

enum AppChrome {
    static let railPadding: CGFloat = 16
    static let railSectionSpacing: CGFloat = 18
    /// Must match `DashboardView` frame on `LeftControlsPanel` so scroll content width is deterministic.
    /// Standard macOS inspector width; `ControlSliderView` puts Setpoint and Variation on separate rows so nothing clips.
    static let liveControlRailOuterWidth: CGFloat = 280
    /// Scroll column width inside the rail (after `railPadding` only). Stops tab bodies from sizing to intrinsic width.
    static var liveControlScrollViewportWidth: CGFloat {
        liveControlRailOuterWidth - 2 * railPadding
    }
    /// Sole horizontal inset for live-controls tab scroll content (Wind / Env / … / Boat share this width model).
    static let liveControlContentHorizontalPadding: CGFloat = 0
    static let railDivider = Color.white.opacity(0.08)
    static let subtleFill = Color.white.opacity(0.04)
    static let raisedFill = Color.white.opacity(0.06)
}

struct RailHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RailSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RailHeader(title, subtitle: subtitle)
            content
        }
        .padding(.vertical, 2)
    }
}

struct RailDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppChrome.railDivider)
            .frame(height: 1)
    }
}

// MARK: - Live controls shared layout (one width model + one section chrome)
//
// ScrollView content must not derive its width from intrinsic control size (sliders vs pickers differ),
// or switching tabs will resize the column horizontally. `LiveControlsTabPage` pins
// `AppChrome.liveControlScrollViewportWidth`; keep `liveControlRailOuterWidth` aligned with `DashboardView`.

/// Wraps every live-controls tab body: fixed scroll width + shared inset so sliders and pickers cannot change the column width.
struct LiveControlsTabPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.top, 2)
            .padding(.horizontal, AppChrome.liveControlContentHorizontalPadding)
            .frame(width: AppChrome.liveControlScrollViewportWidth, alignment: .leading)
    }
}

/// Shared “headline + subtitle + value” stack and vertical padding used by slider stripes and boat stripes.
/// Live strings are stored values rendered here. A trailing closure captured the first number and did not refresh.
struct LiveControlRailBlock<Content: View>: View {
    let title: String
    let subtitle: String
    var trailing: String
    var trailingMonospaced: Bool
    var detail: String?
    var detailMonospaced: Bool
    var detailIdentifier: String?
    var content: Content

    init(
        title: String,
        subtitle: String,
        trailing: String,
        trailingMonospaced: Bool = true,
        detail: String? = nil,
        detailMonospaced: Bool = false,
        detailIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.trailingMonospaced = trailingMonospaced
        self.detail = detail
        self.detailMonospaced = detailMonospaced
        self.detailIdentifier = detailIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            // Leading column expands so title/subtitle use a stable width for every tab; a Spacer+intrinsic
            // stack made headline width depend on the longest line and looked like “resizing” when switching.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if trailingMonospaced {
                        Text(trailing)
                            .monospacedDigit()
                    } else {
                        Text(trailing)
                    }
                }
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }

            if let detail {
                detailText(detail)
            }

            content
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailText(_ detail: String) -> some View {
        let text = Group {
            if detailMonospaced {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
            } else {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)

        if let detailIdentifier {
            text.accessibilityIdentifier(detailIdentifier)
        } else {
            text
        }
    }
}

struct ControlSliderView: View {
    @Bindable var nmea: NMEASimulator
    var valuePath: WritableKeyPath<NMEASimulator, SimulatedValue>

    var title: String = "Heading"
    var unit: String = "°"
    var precision: Int = 1
    var sliderRange: ClosedRange<Double>
    var systemImage: String?
    var onChange: (() -> Void)?
    var isDisabled: Bool = false
    var disabledReason: String?
    var supportingNote: String?
    /// When true, ± nudges and setpoint entry wrap through 0° (e.g. 359° + 1° → 0°).
    var wrapsCircularDegrees: Bool = false

    private var stepAmount: Double {
        switch precision {
        case ...0:
            return 1
        case 1:
            return 0.1
        default:
            return 0.01
        }
    }

    private var centerValueBinding: Binding<Double> {
        Binding(
            get: { nmea[keyPath: valuePath].centerValue },
            set: { new in
                var value = nmea[keyPath: valuePath]
                if wrapsCircularDegrees {
                    value.centerValue = wrappedCircularSetpoint(new, range: sliderRange)
                } else {
                    value.centerValue = new.clamped(to: sliderRange)
                }
                nmea.setSimulatedValue(valuePath, to: value)
                onChange?()
            }
        )
    }

    private var offsetBinding: Binding<Double> {
        Binding(
            get: { nmea[keyPath: valuePath].offset },
            set: { new in
                var value = nmea[keyPath: valuePath]
                value.offset = new.clamped(to: 0...180)
                nmea.setSimulatedValue(valuePath, to: value)
                onChange?()
            }
        )
    }

    private func nudgeCenter(by delta: Double) {
        let current = nmea[keyPath: valuePath].centerValue
        if wrapsCircularDegrees {
            centerValueBinding.wrappedValue = wrappedCircularSetpoint(current + delta, range: sliderRange)
        } else {
            centerValueBinding.wrappedValue = current + delta
        }
    }

    private func nudgeOffset(by delta: Double) {
        offsetBinding.wrappedValue = nmea[keyPath: valuePath].offset + delta
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(precision)).grouping(.never))
    }

    private func nudgeRow(
        label: String,
        identifier: String,
        binding: Binding<Double>,
        nudge: @escaping (Double) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.row) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: DesignToken.Spacing.related)

            ValueNudgeButton(systemImage: "minus", isDisabled: isDisabled) {
                nudge(-stepAmount)
            }

            TextField(
                label,
                value: binding,
                format: .number.precision(.fractionLength(precision)).grouping(.never)
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: 72)
            .disabled(isDisabled)
            .accessibilityIdentifier(identifier)

            ValueNudgeButton(systemImage: "plus", isDisabled: isDisabled) {
                nudge(stepAmount)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text("Live output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SimulatedReadingText(
                    nmea: nmea,
                    valuePath: valuePath,
                    title: title,
                    unit: unit,
                    precision: precision
                )
            }

            nudgeRow(
                label: "Setpoint",
                identifier: "Setpoint \(title)",
                binding: centerValueBinding,
                nudge: nudgeCenter(by:)
            )

            nudgeRow(
                label: "Variation",
                identifier: "Variation \(title)",
                binding: offsetBinding,
                nudge: nudgeOffset(by:)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sweep")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatted(sliderRange.lowerBound)) - \(formatted(sliderRange.upperBound)) \(unit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: centerValueBinding, in: sliderRange)
                    .disabled(isDisabled)
            }
            .disabled(isDisabled)

            if let message = disabledReason ?? supportingNote {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(disabledReason == nil ? .secondary : AppColors.warning)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

extension NMEASimulator {
    func setSimulatedValue(_ keyPath: WritableKeyPath<NMEASimulator, SimulatedValue>, to value: SimulatedValue) {
        if keyPath == \.twd { twd = value }
        else if keyPath == \.tws { tws = value }
        else if keyPath == \.speed { speed = value }
        else if keyPath == \.depth { depth = value }
        else if keyPath == \.seaTemp { seaTemp = value }
        else if keyPath == \.airTemp { airTemp = value }
        else if keyPath == \.humidity { humidity = value }
        else if keyPath == \.barometer { barometer = value }
        else if keyPath == \.heading { heading = value }
        else if keyPath == \.gyroHeading {
            // The gyro setpoint commands true heading. The tick still samples the magnetic
            // center and publishes the gyro as a copy of that true heading, so the command
            // has to be stored there. The gyro value stays the live measurement.
            adoptTrueHeadingCommand(value)
            gyroHeading = value
        }
    }

    /// Converts an operator true-heading command into the magnetic sample the tick steers from.
    /// Sensor switches do not choose the sample; this runs only for the heading-setpoint editor.
    private func adoptTrueHeadingCommand(_ commanded: SimulatedValue) {
        guard sensorToggles.hasGyro, isApplyingSimulationTick == false, isTackInProgress == false else { return }
        guard activeManeuver?.drivesHeading != true else { return }
        let variation = simulatedMagneticVariation(for: gpsData, at: .now)
        let magneticCenter = normalizeAngle(commanded.centerValue - variation)
        guard magneticCenter != heading.centerValue || commanded.offset != heading.offset else { return }
        var magnetic = heading
        magnetic.centerValue = magneticCenter
        magnetic.offset = commanded.offset
        heading = magnetic
    }
}

/// Reads one simulated channel in this body and draws it as static text.
/// The key-path read stays here so the readout subscribes on its own, apart from the editable setpoint field.
private struct SimulatedReadingText: View {
    @Bindable var nmea: NMEASimulator
    var valuePath: WritableKeyPath<NMEASimulator, SimulatedValue>
    var title: String
    var unit: String
    var precision: Int

    var body: some View {
        let current = nmea[keyPath: valuePath]
        let reading = current.value ?? current.centerValue
        let label = "\(formatted(reading)) \(unit)"
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.noteReading(title, label)
        #endif
        Text(label)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("Reading \(title)")
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(precision)).grouping(.never))
    }
}

private struct ValueNudgeButton: View {
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}
