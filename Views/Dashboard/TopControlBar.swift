//
//  TopControlBar.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 4.10.25.
//

import SwiftUI

struct TopControlBar: View {
    @Environment(NMEASimulator.self) private var nmea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var showLeft: Bool
    @Binding var showRight: Bool
    @Binding var showBottom: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideLayout
            narrowLayout
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 18) {
            panelsSection

            toolbarSection("Scenario") {
                HStack(spacing: 8) {
                    ForEach(SimulationPreset.allCases) { preset in
                        PresetControl(
                            preset: preset,
                            isSelected: nmea.weatherSourceMode == .manual && (nmea.selectedPreset ?? .lightWeather) == preset,
                            isDisabled: nmea.weatherSourceMode == .liveWeather,
                            showCaption: true
                        ) {
                            nmea.applyPreset(preset)
                        }
                    }
                }
            }

            statusSection

            if nmea.weatherSourceMode == .liveWeather {
                toolbarSection("Weather") {
                    LiveWeatherSnapshotStrip(
                        mode: nmea.weatherSourceMode,
                        status: nmea.liveWeatherStatus,
                        snapshot: nmea.latestLiveWeather,
                        showUpdatedInPopover: true
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var narrowLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            panelsSection

            Menu {
                Section("Scenario") {
                    ForEach(SimulationPreset.allCases) { preset in
                        Button {
                            nmea.applyPreset(preset)
                        } label: {
                            Label(preset.displayName, systemImage: presetSymbol(preset))
                        }
                        .disabled(nmea.weatherSourceMode == .liveWeather)
                    }
                }

                Section("Status") {
                    Button {
                        nmea.weatherSourceMode = nmea.weatherSourceMode == .manual ? .liveWeather : .manual
                    } label: {
                        Label(
                            nmea.weatherSourceMode == .liveWeather ? "Switch To Manual Weather" : "Switch To Live Weather",
                            systemImage: nmea.weatherSourceMode == .liveWeather ? "slider.horizontal.3" : "cloud.sun.fill"
                        )
                    }

                    if let preset = nmea.selectedPreset, nmea.weatherSourceMode == .manual {
                        Text("Preset: \(preset.displayName)")
                    }

                    if nmea.sensorToggles.hasGyro {
                        Text("Gyro Priority")
                    } else if nmea.sensorToggles.hasCompass {
                        Text("Magnetic Fallback")
                    }

                    if nmea.boatSpeedMode == .estimated {
                        Text("Boat: \(nmea.boatProfile.shortName)")
                    }
                }

                if nmea.weatherSourceMode == .liveWeather {
                    Section("Weather") {
                        LiveWeatherSnapshotStrip(
                            mode: nmea.weatherSourceMode,
                            status: nmea.liveWeatherStatus,
                            snapshot: nmea.latestLiveWeather,
                            showUpdatedInPopover: true
                        )
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)

            Spacer(minLength: 0)
        }
    }

    private var panelsSection: some View {
        toolbarSection("Panels") {
            HStack(spacing: 8) {
                ToggleIcon("slider.horizontal.below.rectangle", title: "Controls", isOn: $showLeft, reduceMotion: reduceMotion)
                ToggleIcon("gauge.with.needle", title: "Instruments", isOn: $showRight, reduceMotion: reduceMotion)
                ToggleIcon("terminal", title: "Console Log", isOn: $showBottom, reduceMotion: reduceMotion)
            }
        }
    }

    private var statusSection: some View {
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

                if nmea.boatSpeedMode == .estimated {
                    statusBadge(title: nmea.boatProfile.shortName, systemImage: "sailboat", tint: .mint.opacity(0.75))
                }
            }
        }
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

    private func presetSymbol(_ preset: SimulationPreset) -> String {
        switch preset {
        case .harborCalm: return "drop"
        case .lightWeather: return "cloud.sun"
        case .stormyWeather: return "hurricane"
        }
    }
}

private struct LiveWeatherSnapshotStrip: View {
    let mode: WeatherSourceMode
    let status: LiveWeatherStatus
    let snapshot: LiveWeatherSnapshot?
    var showUpdatedInPopover: Bool = false

    @State private var showDetails = false

    var body: some View {
        Button {
            if showUpdatedInPopover {
                showDetails = true
            }
        } label: {
            HStack(spacing: 8) {
                statusSummary
                providerSummary
            }
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Live Weather")
                    .font(.headline)

                if let lastUpdated = status.lastUpdated {
                    LabeledContent("Updated") {
                        Text(lastUpdated, style: .time)
                    }
                } else {
                    Text("Not fetched yet")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Source") {
                    Text(sourceSummary)
                }

                if let marineSummary {
                    LabeledContent("Marine") {
                        Text(marineSummary.replacingOccurrences(of: "Marine: ", with: ""))
                    }
                }

                LabeledContent("State") {
                    Text(statusLabel.isEmpty ? statusIcon : statusLabel)
                }
            }
            .padding(14)
            .frame(minWidth: 240)
        }
        .help(showUpdatedInPopover ? "Show weather fetch details" : sourceSummary)
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

    private var providerSummary: some View {
        HStack(spacing: 8) {
            Text(sourceSummary)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            if let marineSummary {
                Text(marineSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var sourceSummary: String {
        switch mode {
        case .manual:
            return "Manual controls"
        case .liveWeather:
            return snapshot?.sourceName ?? "Live weather"
        }
    }

    private var marineSummary: String? {
        guard mode == .liveWeather else { return nil }
        guard let marineSource = snapshot?.marineSourceName else { return nil }
        return "Marine: \(marineSource)"
    }

    private var statusLabel: String {
        switch status.state {
        case .idle: return ""
        case .fetching: return "Fetching"
        case .ready: return ""
        case .failed: return "Error"
        }
    }

    private var statusIcon: String {
        switch status.state {
        case .idle: return "cloud"
        case .fetching: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status.state {
        case .idle: return .secondary
        case .fetching: return .orange
        case .ready: return .cyan
        case .failed: return .red
        }
    }
}

private struct WeatherModeIconButton: View {
    let mode: WeatherSourceMode
    let action: () -> Void

    private var systemImage: String {
        mode == .liveWeather ? "slider.horizontal.3" : "cloud.sun.fill"
    }

    private var title: String {
        mode == .liveWeather ? "Switch To Manual Weather" : "Switch To Live Weather"
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
    let reduceMotion: Bool

    init(_ sf: String, title: String, isOn: Binding<Bool>, reduceMotion: Bool) {
        self.sf = sf
        self.title = title
        self._isOn = isOn
        self.reduceMotion = reduceMotion
    }

    var body: some View {
        Button {
            if reduceMotion {
                isOn.toggle()
            } else {
                withAnimation(.snappy(duration: 0.24)) { isOn.toggle() }
            }
        } label: {
            Image(systemName: sf)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(isOn ? AppChrome.raisedFill : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct PresetControl: View {
    let preset: SimulationPreset
    let isSelected: Bool
    let isDisabled: Bool
    let showCaption: Bool
    let action: () -> Void

    private var symbolName: String {
        switch preset {
        case .harborCalm: return "drop"
        case .lightWeather: return "cloud.sun"
        case .stormyWeather: return "hurricane"
        }
    }

    var body: some View {
        Button(action: action) {
            if showCaption {
                VStack(spacing: 4) {
                    Image(systemName: symbolName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(preset.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(minWidth: 56)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AppColors.success.opacity(0.22) : AppChrome.subtleFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AppColors.success.opacity(0.45) : .white.opacity(0.08))
                )
            } else {
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
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(isDisabled ? "Presets are disabled while Live Weather mode is active." : preset.displayName + ". " + preset.summary)
    }
}
