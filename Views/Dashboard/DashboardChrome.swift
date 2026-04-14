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
    /// Wide enough for `ControlSliderView` (setpoint + variation stepper) without clipping; Boat tab pickers still fit.
    static let liveControlRailOuterWidth: CGFloat = 352
    /// Scroll column width inside the rail (after `railPadding` only). Stops tab bodies from sizing to intrinsic width.
    static var liveControlScrollViewportWidth: CGFloat {
        liveControlRailOuterWidth - 2 * railPadding
    }
    /// Sole horizontal inset for live-controls tab scroll content (Wind / Env / … / Boat share this width model).
    static let liveControlContentHorizontalPadding: CGFloat = 10
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
struct LiveControlRailBlock<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

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

                trailing()
                    .multilineTextAlignment(.trailing)
            }

            content()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ControlSliderView: View {

    @Binding var value: SimulatedValue

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

    private var displayValue: Double {
        value.value ?? value.centerValue
    }

    private var centerValueBinding: Binding<Double> {
        Binding(
            get: { value.centerValue },
            set: { new in
                if wrapsCircularDegrees {
                    value.centerValue = wrappedCircularSetpoint(new, range: sliderRange)
                } else {
                    value.centerValue = new.clamped(to: sliderRange)
                }
                notifyPersist()
            }
        )
    }

    private var offsetBinding: Binding<Double> {
        Binding(
            get: { value.offset },
            set: { new in
                value.offset = new
                notifyPersist()
            }
        )
    }

    private func notifyPersist() {
        onChange?()
    }

    private func nudgeCenter(by delta: Double) {
        if wrapsCircularDegrees {
            value.centerValue = wrappedCircularSetpoint(value.centerValue + delta, range: sliderRange)
        } else {
            value.centerValue = (value.centerValue + delta).clamped(to: sliderRange)
        }
        notifyPersist()
    }

    var body: some View {
        LiveControlRailBlock(title: title, subtitle: "Live output", trailing: {
            Text("\(displayValue.formatted(.number.precision(.fractionLength(precision)))) \(unit)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }, content: {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                HStack(alignment: .center, spacing: 8) {
                    ValueNudgeButton(systemImage: "minus", isDisabled: isDisabled) {
                        nudgeCenter(by: -stepAmount)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Setpoint")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("", value: centerValueBinding, format: .number.precision(.fractionLength(precision)))
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 84)
                            .disabled(isDisabled)
                    }

                    ValueNudgeButton(systemImage: "plus", isDisabled: isDisabled) {
                        nudgeCenter(by: stepAmount)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Variation")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Stepper(
                            "\(value.offset.formatted(.number.precision(.fractionLength(precision))))",
                            value: offsetBinding,
                            in: 0...180,
                            step: stepAmount
                        )
                        .monospacedDigit()
                        .frame(minWidth: 96, maxWidth: 104, alignment: .trailing)
                        .disabled(isDisabled)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sweep")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(sliderRange.lowerBound.formatted(.number.precision(.fractionLength(precision)))) - \(sliderRange.upperBound.formatted(.number.precision(.fractionLength(precision)))) \(unit)")
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
        })
        .opacity(isDisabled ? 0.55 : 1)
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
