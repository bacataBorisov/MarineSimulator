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
            HStack(alignment: .top, spacing: 18) {
                toolbarSection("Panels") {
                    HStack(spacing: 8) {
                        ToggleIcon("slider.horizontal.below.rectangle", title: "Controls", isOn: $showLeft)
                        ToggleIcon("gauge.with.needle", title: "Instruments", isOn: $showRight)
                        ToggleIcon("terminal", title: "Console", isOn: $showBottom)
                    }
                }

                toolbarSection("Scenario") {
                    HStack(spacing: 8) {
                        ForEach(SimulationPreset.allCases) { preset in
                            PresetIconButton(
                                preset: preset,
                                isSelected: nmea.weatherSourceMode == .manual && (nmea.selectedPreset ?? .lightWeather) == preset,
                                isDisabled: nmea.weatherSourceMode == .liveWeather
                            ) {
                                nmea.applyPreset(preset)
                            }
                        }
                    }
                }

                toolbarSection("Status") {
                    HStack(spacing: 8) {
                        WeatherModeIconButton(mode: nmea.weatherSourceMode) {
                            nmea.weatherSourceMode = nmea.weatherSourceMode == .manual ? .liveWeather : .manual
                        }

                        statusBadge(
                            title: nmea.weatherSourceMode == .liveWeather ? "Live Weather" : "Manual Weather",
                            systemImage: nmea.weatherSourceMode == .liveWeather ? "cloud.sun.fill" : "slider.horizontal.3",
                            tint: nmea.weatherSourceMode == .liveWeather ? .cyan.opacity(0.78) : .gray.opacity(0.7)
                        )

                        if let preset = nmea.selectedPreset {
                            statusBadge(
                                title: preset.displayName,
                                systemImage: "cloud.sun",
                                tint: nmea.weatherSourceMode == .manual ? .blue.opacity(0.75) : .gray.opacity(0.45),
                                isActive: nmea.weatherSourceMode == .manual
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

            if nmea.weatherSourceMode == .liveWeather {
                LiveWeatherSnapshotStrip(
                    status: nmea.liveWeatherStatus,
                    snapshot: nmea.latestLiveWeather
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolbarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            content()
        }
    }

    @ViewBuilder
    private func statusBadge(title: String, systemImage: String, tint: Color, isActive: Bool = true) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? tint.opacity(0.12) : .white.opacity(0.06), lineWidth: 1)
            }
            .opacity(isActive ? 1 : 0.55)
    }
}

private struct LiveWeatherSnapshotStrip: View {
    let status: LiveWeatherStatus
    let snapshot: LiveWeatherSnapshot?

    var body: some View {
        HStack(spacing: 10) {
            statusSummary

            if let snapshot {
                summaryRow(for: snapshot)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(status.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSummary: some View {
        Group {
            if statusLabel.isEmpty {
                Image(systemName: statusIcon)
            } else {
                Label(statusLabel, systemImage: statusIcon)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(statusColor)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func summaryRow(for snapshot: LiveWeatherSnapshot) -> some View {
        HStack(spacing: 12) {
            summaryValue("TWD", value: shortDegrees(snapshot.trueWindDirection))
            summaryValue("TWS", value: shortKnots(snapshot.trueWindSpeedKnots))
            summaryValue("Gust", value: shortKnots(snapshot.windGustSpeedKnots))
            summaryValue("Sea", value: shortCelsius(snapshot.seaSurfaceTemperatureCelsius))
            summaryValue("Air", value: shortCelsius(snapshot.airTemperatureCelsius))
            summaryValue("Hum", value: shortPercent(snapshot.relativeHumidityPercent))
            summaryValue("Press", value: shortPressure(snapshot.airPressureHectopascals))
        }
        .lineLimit(1)
    }

    private var statusLabel: String {
        switch status.state {
        case .idle:
            return "Live Weather Idle"
        case .fetching:
            return "Fetching Live Weather"
        case .ready:
            return ""
        case .failed:
            return "Live Weather Error"
        }
    }

    private var statusIcon: String {
        switch status.state {
        case .idle:
            return "cloud"
        case .fetching:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status.state {
        case .idle:
            return .secondary
        case .fetching:
            return .orange
        case .ready:
            return .cyan
        case .failed:
            return .red
        }
    }

    @ViewBuilder
    private func summaryValue(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .fixedSize()
    }

    private func shortDegrees(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f°", value)
    }

    private func shortKnots(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f kn", value)
    }

    private func shortCelsius(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f °C", value)
    }

    private func shortPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value)
    }
}

private func shortPressure(_ value: Double?) -> String {
    guard let value else {
        return "--"
    }
    return "\(Int(value.rounded())) hPa"
}

private struct WeatherModeIconButton: View {
    let mode: WeatherSourceMode
    let action: () -> Void

    private var systemImage: String {
        switch mode {
        case .manual:
            return "cloud.sun"
        case .liveWeather:
            return "hand.raised"
        }
    }

    private var title: String {
        switch mode {
        case .manual:
            return "Switch To Live Weather"
        case .liveWeather:
            return "Switch To Manual Weather"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(
                    mode == .liveWeather ? AppColors.info.opacity(0.18) : AppChrome.subtleFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(mode == .liveWeather ? AppColors.info.opacity(0.40) : .white.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .help(title)
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
    let isDisabled: Bool
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
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(isDisabled ? "Presets are disabled while Live Weather mode is active." : preset.displayName + ". " + preset.summary)
    }
}
