//
//  LeftControlsPanel.swift
//  NMEASimulator
//
//  Drop-in compact controls panel
//

import SwiftUI
import Observation

// MARK: - Category Enum
enum ControlCategory: String, CaseIterable {
    case wind = "Wind"
    case environment = "Environment"
    case hydro = "Hydro"
    case heading = "Heading"
    case boat = "Boat"

    /// Short labels so five segments fit the dashboard rail while keeping one unified segmented control (same container as every tab).
    var segmentTitle: String {
        switch self {
        case .wind: "Wind"
        case .environment: "Env"
        case .hydro: "Hydro"
        case .heading: "Heading"
        case .boat: "Boat"
        }
    }

    var systemImage: String {
        switch self {
        case .wind: "wind"
        case .environment: "cloud.sun"
        case .hydro: "drop"
        case .heading: "location.north.line"
        case .boat: "sailboat"
        }
    }
}

// MARK: - Main Left Panel
struct LeftControlsPanel: View {
    @Bindable var nmea: NMEASimulator
    @AppStorage("dashboard.live_control_category") private var category: ControlCategory = .wind

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignToken.Spacing.row) {
                ForEach(ControlCategory.allCases, id: \.self) { cat in
                    let isSelected = category == cat
                    Button {
                        category = cat
                    } label: {
                        Image(systemName: cat.systemImage)
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                            .frame(width: 34, height: 30)
                            .foregroundStyle(isSelected ? DesignToken.accentPrimary : .secondary)
                            .background(
                                isSelected ? DesignToken.accentPrimary.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: DesignToken.Radius.status, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: DesignToken.Radius.status, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(cat.rawValue)
                    .accessibilityLabel(cat.rawValue)
                    .accessibilityIdentifier("ControlTab \(cat.rawValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    if cat != ControlCategory.allCases.last {
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, DesignToken.Spacing.inset)

            RailDivider()

            ScrollView {
                LiveControlsTabPage {
                    Group {
                        switch category {
                        case .wind: WindControls(nmea: nmea)
                        case .environment: EnvironmentControls(nmea: nmea)
                        case .hydro: HydroControls(nmea: nmea)
                        case .heading: HeadingControls(nmea: nmea)
                        case .boat: BoatControls(nmea: nmea, chrome: .dashboardRail)
                        }
                    }
                    .animation(nil, value: category)
                }
            }
            .scrollIndicators(.never)
            .frame(width: AppChrome.liveControlScrollViewportWidth)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, AppChrome.railPadding)
        .padding(.bottom, AppChrome.railPadding)
        .frame(width: AppChrome.liveControlRailOuterWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

// MARK: - Compact Control Row
struct CompactControlRow: View {
    let title: String
    let unit: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    var step: Double = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value, specifier: value < 10 ? "%.1f" : "%.0f") \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Slider + stepper + text field (stable across SDKs)
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .frame(width: 60)
                DeferredNumericField(value: $value, fractionDigits: 1, width: 64)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Angle Knob


// MARK: - Wind Controls
struct WindControls: View {
    @Bindable var nmea: NMEASimulator
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlSliderView(
                nmea: nmea,
                valuePath: \.twd,
                title: "True Wind Direction",
                unit: "°",
                precision: 0,
                sliderRange: SimulatedValueType.windDirection.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasAnemometer || nmea.liveWeatherControlsWind,
                disabledReason: windDisabledReason,
                wrapsCircularDegrees: true
            )
            RailDivider()
            ControlSliderView(
                nmea: nmea,
                valuePath: \.tws,
                title: "True Wind Speed",
                unit: "kn",
                precision: 1,
                sliderRange: SimulatedValueType.windSpeed.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasAnemometer || nmea.liveWeatherControlsWind,
                disabledReason: windDisabledReason
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var windDisabledReason: String? {
        if !nmea.sensorToggles.hasAnemometer {
            return "Enable the Anemometer in Configuration to control wind."
        }

        if nmea.liveWeatherControlsWind {
            return "Live Weather mode is driving wind from the boat's current GPS position."
        }

        return nil
    }
}

// MARK: - Boat Controls
enum BoatControlsChrome {
    /// Dashboard rail: thin `RailDivider` like other live-control tabs.
    case dashboardRail
    /// Setup / GroupBox: standard `Divider` so spacing matches Configuration-style forms.
    case setupForm
}

struct BoatControls: View {
    @Bindable var nmea: NMEASimulator
    var chrome: BoatControlsChrome = .dashboardRail

    var body: some View {
        let windAngle = nmea.maneuverAbsoluteTrueWindAngle
        let sailing = nmea.liveSailingState
        let tackName = sailing.tack == .port ? "Port" : (sailing.tack == .starboard ? "Starboard" : "—")
        let sailName = sailing.sailCombination?.rawValue ?? "—"
        let sailingReadout = "\(sailing.pointOfSail.displayName) · \(tackName) · TWA \(String(format: "%.0f", sailing.absoluteTrueWindAngle))° · Sail \(sailName)"
        let vesselName = nmea.activeVesselName
        let vesselSummary = nmea.activeVesselSummary

        VStack(alignment: .leading, spacing: 0) {
            LiveControlRailBlock(
                title: "Vessel",
                subtitle: "Active profile",
                trailing: vesselName,
                trailingMonospaced: false,
                detail: vesselSummary
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.row) {
                        Text("Profile")
                            .font(DesignToken.Typography.supporting)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: DesignToken.Spacing.related)
                        VesselPicker(nmea: nmea)
                            .frame(width: 152, alignment: .trailing)
                    }

                    if let active = nmea.vessels.first(where: { $0.id == nmea.selectedVesselID }) {
                        ActiveSailControls(
                            profile: active,
                            target: .hoisted,
                            simulator: nmea,
                            compactRail: chrome == .dashboardRail
                        )
                    }

                    Picker("Boat Speed Model", selection: Binding(
                        get: { nmea.selectedVesselID == nil ? .manual : nmea.boatSpeedMode },
                        set: { nmea.boatSpeedMode = $0 }
                    )) {
                        ForEach(BoatSpeedMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(nmea.selectedVesselID == nil)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Boat Speed Model")
                }
            }

            chromeSeparator

            LiveControlRailBlock(
                title: "Maneuver",
                subtitle: "Through the wind",
                trailing: windAngle.map { "±\(String(format: "%.1f", $0))°" } ?? "—",
                detail: sailingReadout,
                detailMonospaced: true
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tack crosses the bow. Gybe crosses the stern.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            maneuverButton(.tack(.port), title: "Tack Port")
                            maneuverButton(.tack(.starboard), title: "Tack Stbd")
                        }
                        GridRow {
                            maneuverButton(.gybe(.port), title: "Gybe Port")
                            maneuverButton(.gybe(.starboard), title: "Gybe Stbd")
                        }
                    }

                    Button("Cancel") {
                        nmea.cancelManeuver()
                    }
                    .controlSize(.small)
                    .disabled(nmea.vesselObservation.maneuverPhase == .idle && !nmea.isTackInProgress)

                    if let reason = tackDisabledReason ?? nmea.maneuverRejectionReason ?? nmea.sailingPolicyExplanation {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DisclosureGroup("Duration and speed loss") {
                        VStack(alignment: .leading, spacing: 8) {
                            durationRow(
                                title: "Tack duration",
                                enabled: $nmea.maneuverSettings.usesTackDuration,
                                seconds: $nmea.maneuverSettings.tackDurationSeconds
                            )
                            durationRow(
                                title: "Gybe duration",
                                enabled: $nmea.maneuverSettings.usesGybeDuration,
                                seconds: $nmea.maneuverSettings.gybeDurationSeconds
                            )
                            retentionRow(title: "Tack keeps", value: $nmea.maneuverSettings.tackSpeedRetention)
                            retentionRow(title: "Gybe keeps", value: $nmea.maneuverSettings.gybeSpeedRetention)
                            Text("Off means duration follows the turn. Recovery uses the existing speed model. The heading eases on a smooth step.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
            }
        }
        .onChange(of: sailing.pointOfSail) { _, _ in
            nmea.maneuverRejectionReason = nil
        }
        .onChange(of: sailing.tack) { _, _ in
            nmea.maneuverRejectionReason = nil
        }
    }

    private func maneuverButton(_ command: ManeuverCommand, title: String) -> some View {
        let active = nmea.isTackInProgress && nmea.activeManeuver?.kind == command.kind && nmea.activeManeuver?.side == command.side
        return Button {
            nmea.beginManeuver(command)
        } label: {
            Text(active ? "In progress" : title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(nmea.selectedVesselID == nil || !nmea.canExecuteTackManeuver || !nmea.maneuverCommandIsAvailable(command))
    }

    private func durationRow(title: String, enabled: Binding<Bool>, seconds: Binding<Double>) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
                .font(.caption)
            Spacer(minLength: 8)
            Stepper(value: seconds, in: 1...60, step: 1) {
                Text(enabled.wrappedValue ? "\(Int(seconds.wrappedValue)) s" : "Auto")
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
            }
            .disabled(!enabled.wrappedValue)
            .controlSize(.small)
        }
    }

    private func retentionRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var chromeSeparator: some View {
        switch chrome {
        case .dashboardRail:
            RailDivider()
        case .setupForm:
            Divider()
                .padding(.vertical, 2)
        }
    }

    private var tackDisabledReason: String? {
        if nmea.selectedVesselID == nil {
            return "Select a boat profile above to enable maneuvers and sail modeling."
        }
        if nmea.isTackInProgress {
            return nil
        }
        if !nmea.sensorToggles.hasAnemometer {
            return "Enable the Anemometer in Configuration to use tack (needs true wind direction)."
        }
        if !nmea.sensorToggles.hasGyro && !nmea.sensorToggles.hasCompass {
            return "Enable the Gyro or Magnetic Compass to animate heading through the tack."
        }
        return nil
    }
}

// MARK: - Hydro Controls
struct HydroControls: View {
    @Bindable var nmea: NMEASimulator
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlSliderView(
                nmea: nmea,
                valuePath: \.speed,
                title: "Speed Through Water",
                unit: "kn",
                precision: 1,
                sliderRange: SimulatedValueType.speedLog.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasSpeedLog || nmea.boatSpeedMode == .estimated,
                disabledReason: speedDisabledReason
            )
            RailDivider()
            ControlSliderView(
                nmea: nmea,
                valuePath: \.depth,
                title: "Depth",
                unit: "m",
                precision: 1,
                sliderRange: SimulatedValueType.depth.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasEchoSounder,
                disabledReason: !nmea.sensorToggles.hasEchoSounder ? "Enable the Echo Sounder in Configuration to control depth." : nil
            )
            RailDivider()
            ControlSliderView(
                nmea: nmea,
                valuePath: \.seaTemp,
                title: "Sea Water Temperature",
                unit: "°C",
                precision: 1,
                sliderRange: SimulatedValueType.seaTemp.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasWaterTempSensor || nmea.liveWeatherControlsSeaTemperature,
                disabledReason: seaTemperatureDisabledReason
            )
        }
    }

    private var seaTemperatureDisabledReason: String? {
        if !nmea.sensorToggles.hasWaterTempSensor {
            return "Enable the Water Temperature sensor in Configuration to control sea temperature."
        }

        if nmea.liveWeatherControlsSeaTemperature {
            return "Live Weather mode is driving sea temperature from the boat's current GPS position."
        }

        return nil
    }

    private var speedDisabledReason: String? {
        if !nmea.sensorToggles.hasSpeedLog {
            return "Enable the Speed Log in Configuration to control water speed."
        }

        if nmea.boatSpeedMode == .estimated {
            return "Boat speed is currently estimated from wind, heading, and the selected boat profile."
        }

        return nil
    }
}

// MARK: - Heading Controls
struct HeadingControls: View {
    @Bindable var nmea: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeadingStatusText(nmea: nmea)

            RailDivider()

            ControlSliderView(
                nmea: nmea,
                valuePath: \.gyroHeading,
                title: "Gyro Compass (True)",
                unit: "°",
                precision: 0,
                sliderRange: SimulatedValueType.gyroCompass.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasGyro || nmea.isTackInProgress,
                disabledReason: headingDisabledReason(hasSensor: nmea.sensorToggles.hasGyro, sensorName: "Gyro Compass"),
                supportingNote: "Commands true heading (HDT / ROT).",
                wrapsCircularDegrees: true
            )

            RailDivider()

            ControlSliderView(
                nmea: nmea,
                valuePath: \.heading,
                title: "Magnetic Compass",
                unit: "°",
                precision: 0,
                sliderRange: SimulatedValueType.magneticCompass.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasCompass || nmea.isTackInProgress,
                disabledReason: headingDisabledReason(hasSensor: nmea.sensorToggles.hasCompass, sensorName: "Magnetic Compass"),
                supportingNote: "Commands magnetic heading (HDG). Editing Gyro updates this via local variation.",
                wrapsCircularDegrees: true
            )
        }
    }

    private func headingDisabledReason(hasSensor: Bool, sensorName: String) -> String? {
        if nmea.isTackInProgress {
            return "A maneuver owns heading. Cancel it to steer manually."
        }
        if !hasSensor {
            return "Enable the \(sensorName) in Simulation to control heading."
        }
        return nil
    }
}

/// Reads gyro and magnetic heading in this body and renders them as static text.
private struct HeadingStatusText: View {
    @Bindable var nmea: NMEASimulator

    var body: some View {
        let gyro = gyroText
        let magnetic = magneticText
        let readout = "Gyro \(gyro) · Magnetic \(magnetic)"
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.noteReading("Heading Status", readout)
        #endif
        LiveControlRailBlock(
            title: "Compass",
            subtitle: "Live measurements",
            trailing: nmea.sensorToggles.hasGyro ? gyro : magnetic,
            detail: readout,
            detailMonospaced: true,
            detailIdentifier: "Heading Status"
        ) {
            EmptyView()
        }
    }

    private var gyroText: String {
        guard nmea.sensorToggles.hasGyro else { return "off" }
        let value = nmea.gyroHeading.value ?? nmea.gyroHeading.centerValue
        return "\(Int(value.rounded()))°"
    }

    private var magneticText: String {
        guard nmea.sensorToggles.hasCompass else { return "off" }
        let value = nmea.heading.value ?? nmea.heading.centerValue
        return "\(Int(value.rounded()))°"
    }
}

struct EnvironmentControls: View {
    @Bindable var nmea: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlSliderView(
                nmea: nmea,
                valuePath: \.airTemp,
                title: "Air Temperature",
                unit: "°C",
                precision: 1,
                sliderRange: SimulatedValueType.airTemp.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasAirTempSensor || nmea.liveWeatherControlsAirTemperature,
                disabledReason: airTemperatureDisabledReason
            )
            RailDivider()
            ControlSliderView(
                nmea: nmea,
                valuePath: \.humidity,
                title: "Relative Humidity",
                unit: "%",
                precision: 0,
                sliderRange: SimulatedValueType.humidity.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasHumidtySensor || nmea.liveWeatherControlsHumidity,
                disabledReason: humidityDisabledReason
            )
            RailDivider()
            ControlSliderView(
                nmea: nmea,
                valuePath: \.barometer,
                title: "Barometer",
                unit: "hPa",
                precision: 1,
                sliderRange: SimulatedValueType.barometer.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasBarometer || nmea.liveWeatherControlsBarometer,
                disabledReason: barometerDisabledReason
            )
        }
    }

    private var airTemperatureDisabledReason: String? {
        if !nmea.sensorToggles.hasAirTempSensor {
            return "Enable the Air Temperature sensor in Configuration to control air temperature."
        }

        if nmea.liveWeatherControlsAirTemperature {
            return "Live Weather mode is driving air temperature from the boat's current GPS position."
        }

        return nil
    }

    private var humidityDisabledReason: String? {
        if !nmea.sensorToggles.hasHumidtySensor {
            return "Enable the Humidity sensor in Configuration to control relative humidity."
        }

        if nmea.liveWeatherControlsHumidity {
            return "Live Weather mode is driving humidity from the boat's current GPS position."
        }

        return nil
    }

    private var barometerDisabledReason: String? {
        if !nmea.sensorToggles.hasBarometer {
            return "Enable the Barometer in Configuration to control air pressure."
        }

        if nmea.liveWeatherControlsBarometer {
            return "Live Weather mode is driving air pressure from the boat's current GPS position."
        }

        return nil
    }
}

// MARK: - Setup (sidebar) boat panel
struct VesselPicker: View {
    @Bindable var nmea: NMEASimulator

    var body: some View {
        Picker("Boat Profile", selection: Binding(
            get: { nmea.selectedVesselID },
            set: { id in
                if let id {
                    nmea.selectVessel(id)
                } else {
                    nmea.clearSelectedVessel()
                }
            }
        )) {
            Text("No Boat (Instruments Only)").tag(Optional<UUID>.none)
            ForEach(nmea.vessels) { vessel in
                Text(vessel.name).tag(Optional(vessel.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Boat Profile")
    }
}

// MARK: - Preview
#Preview {
    LeftControlsPanel(nmea: NMEASimulator())
        .environment(NMEASimulator())
        .frame(width: 340, height: 800)
}
