//
//  TopControlBar.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 4.10.25.
//

import SwiftUI

struct TopControlBar: View {
    @Environment(NMEASimulator.self) private var nmea

    @Binding var showLeft: Bool
    @Binding var showRight: Bool
    @Binding var showBottom: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dashboard")
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 8) {
                        if let preset = nmea.selectedPreset {
                            statusBadge(
                                title: preset.displayName,
                                systemImage: "cloud.sun",
                                tint: .blue.opacity(0.75)
                            )
                        }

                        if nmea.sensorToggles.hasGyro {
                            statusBadge(title: "Gyro Priority", systemImage: "location.north.line", tint: .teal.opacity(0.8))
                        } else if nmea.sensorToggles.hasCompass {
                            statusBadge(title: "Magnetic Fallback", systemImage: "safari", tint: .orange.opacity(0.8))
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    ToggleIcon("slider.horizontal.below.rectangle", title: "Controls", isOn: $showLeft)
                    ToggleIcon("gauge.with.needle", title: "Instruments", isOn: $showRight)
                    ToggleIcon("terminal", title: "Console", isOn: $showBottom)
                }

                Divider()
                    .frame(height: 28)

                HStack(spacing: 8) {
                    ForEach(SimulationPreset.allCases) { preset in
                        PresetIconButton(
                            preset: preset,
                            isSelected: (nmea.selectedPreset ?? .lightWeather) == preset
                        ) {
                            nmea.applyPreset(preset)
                        }
                    }
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusBadge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ToggleIcon: View {
    let sf: String
    let title: String
    @Binding var isOn: Bool

    init(_ sf: String, title: String, isOn: Binding<Bool>) {
        self.sf = sf
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Button { withAnimation(.snappy(duration: 0.24)) { isOn.toggle() } } label: {
            Image(systemName: sf)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(isOn ? AppChrome.raisedFill : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct PresetIconButton: View {
    let preset: SimulationPreset
    let isSelected: Bool
    let action: () -> Void

    private var symbolName: String {
        switch preset {
        case .harborCalm:
            return "drop"
        case .lightWeather:
            return "cloud.sun"
        case .stormyWeather:
            return "hurricane"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(
                    isSelected ? AppColors.success.opacity(0.22) : AppChrome.subtleFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AppColors.success.opacity(0.45) : .white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(preset.displayName + ". " + preset.summary)
    }
}
