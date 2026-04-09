//
//  ViewKit.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 16.06.25.
//


import SwiftUI

struct ViewKit {
    
    static func displayLabel(_ label: String, value: Double?, precision: Int? = 0) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(value.map { String(format: "%.\(precision ?? 0)f", $0) } ?? "--")
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.semibold)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(minWidth: 60, maxWidth: .infinity)
    }
    
    // MARK: - Toggle Row with Optional Info
    
    @ViewBuilder
    static func ToggleRowWithInfo(
        _ title: String,
        systemImage: String? = nil,
        isOn: Binding<Bool>,
        showInfo: Binding<Bool>? = nil,
        infoView: (() -> AnyView)? = nil
    ) -> some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
            
            if let showInfo, let infoView {
                Button {
                    showInfo.wrappedValue = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: showInfo) {
                    infoView()
                        .frame(width: 300, height: 300)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    static func SentenceIntervalControl(
        _ title: String = "Interval",
        interval: Binding<Double>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(value: interval, in: 0...10, step: 0.1) {
                Text(interval.wrappedValue == 0 ? "Every tick" : "\(interval.wrappedValue, specifier: "%.1f") s")
                    .font(.caption)
                    .monospacedDigit()
            }
            .disabled(isDisabled)
        }
        .padding(.leading, 4)
    }
}

enum AppChrome {
    static let railPadding: CGFloat = 16
    static let railSectionSpacing: CGFloat = 18
    static let railDivider = Color.white.opacity(0.08)
    static let subtleFill = Color.white.opacity(0.04)
    static let raisedFill = Color.white.opacity(0.06)
}

extension View {
    /// Applies dimmed opacity if the condition is false
    public func dimmed(if condition: Bool) -> some View {
        self.opacity(condition ? 1.0 : 0.3)
    }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text("Live output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(displayValue.formatted(.number.precision(.fractionLength(precision)))) \(unit)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }

            HStack(alignment: .center, spacing: 12) {
                ValueNudgeButton(systemImage: "minus", isDisabled: isDisabled) {
                    value.centerValue = (value.centerValue - stepAmount).clamped(to: sliderRange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Setpoint")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("", value: $value.centerValue, format: .number.precision(.fractionLength(precision)))
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .frame(width: 92)
                        .disabled(isDisabled)
                }

                ValueNudgeButton(systemImage: "plus", isDisabled: isDisabled) {
                    value.centerValue = (value.centerValue + stepAmount).clamped(to: sliderRange)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Variation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Stepper(
                        "\(value.offset.formatted(.number.precision(.fractionLength(precision))))",
                        value: $value.offset,
                        in: 0...180,
                        step: stepAmount
                    )
                    .monospacedDigit()
                    .frame(width: 108, alignment: .trailing)
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

                CustomSlider(value: $value.centerValue, range: sliderRange)
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
        .opacity(isDisabled ? 0.55 : 1)
        .onChange(of: value) { _, _ in
            onChange?()
        }
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
