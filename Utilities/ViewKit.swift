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
}

extension View {
    /// Applies dimmed opacity if the condition is false
    public func dimmed(if condition: Bool) -> some View {
        self.opacity(condition ? 1.0 : 0.3)
    }
}

struct ControlSliderView: View {
    
    @Binding var value: SimulatedValue
    
    var title: String = "Heading"
    var unit: String = "°"
    var precision: Int = 1
    var sliderRange: ClosedRange<Double>
    var systemImage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            Text(title)
                .font(.headline)
            
            // Center + Offset Controls
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Setpoint")
                        .font(.footnote)
                        .foregroundColor(.primary)

                    TextField("", value: $value.centerValue, format: .number.precision(.fractionLength(precision)))
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                    
                    // Output
                    Text("Output: \(value.value?.formatted(.number.precision(.fractionLength(precision))) ?? "-") \(unit)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                HStack(spacing: 0) {
                    Text("±")
                    Stepper("\(value.offset.formatted(.number.precision(.fractionLength(precision))))", value: $value.offset, in: 0...180, step: 1)
                        .frame(width: 60, alignment: .leading)
                        .monospacedDigit()
                }
            }
            
            // Slider
            CustomSlider(value: $value.centerValue, range: sliderRange)

        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
