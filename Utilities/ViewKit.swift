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

extension View {
    /// Applies dimmed opacity if the condition is false
    public func dimmed(if condition: Bool) -> some View {
        self.opacity(condition ? 1.0 : 0.3)
    }
}
