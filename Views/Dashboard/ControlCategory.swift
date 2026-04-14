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
}

// MARK: - Main Left Panel
struct LeftControlsPanel: View {
    @Bindable var nmea: NMEASimulator
    @State private var category: ControlCategory = .wind

    var body: some View {
        VStack(alignment: .leading, spacing: AppChrome.railSectionSpacing) {
            RailSection("Live Controls", subtitle: "Adjust installed instruments directly from the dashboard. Disabled controls reflect missing sensors.") {
                Picker("Live control category", selection: $category) {
                    ForEach(ControlCategory.allCases, id: \.self) { cat in
                        Text(cat.segmentTitle)
                            .tag(cat)
                            .accessibilityLabel(cat.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(AppChrome.railPadding)
    }
}

// MARK: - Compact Control Row
struct CompactControlRow: View {
    let title: String
    let unit: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    var step: Double = 0.1

    private static let formatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 1
        nf.usesGroupingSeparator = false
        return nf
    }()

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
                TextField("", value: $value, formatter: Self.formatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
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
        @Bindable var nmea = nmea
        VStack(alignment: .leading, spacing: 0) {
            ControlSliderView(
                value: $nmea.twd,
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
                value: $nmea.tws,
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
        @Bindable var nmea = nmea
        let tws = nmea.tws.value ?? nmea.tws.centerValue
        let optimal = nmea.boatProfile.optimalUpwindTrueWindAngleDegrees(trueWindSpeedKnots: tws)

        VStack(alignment: .leading, spacing: 0) {
            LiveControlRailBlock(title: "Boat Speed Model", subtitle: "Live output", trailing: {
                Text(nmea.boatSpeedMode.displayName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }, content: {
                Picker("Boat Speed Model", selection: $nmea.boatSpeedMode) {
                    ForEach(BoatSpeedMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Boat Speed Model")
            })

            chromeSeparator

            LiveControlRailBlock(title: "Boat Profile", subtitle: "Polar basis", trailing: {
                Text(nmea.boatProfile.shortName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }, content: {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Picker("Boat Profile", selection: $nmea.boatProfile) {
                        ForEach(BoatProfile.allCases) { profile in
                            Text(profile.shortName).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Boat Profile")

                    Text(nmea.boatProfile.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            })

            chromeSeparator

            LiveControlRailBlock(title: "Tack", subtitle: "Close-hauled", trailing: {
                Text("±\(optimal, specifier: "%.1f")°")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }, content: {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    Text("Target uses true wind angle ±\(optimal, specifier: "%.1f")° at \(tws, specifier: "%.1f") kn TWS for this profile.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        nmea.beginTackManeuver()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(nmea.isTackInProgress ? "Tacking…" : "Tack")
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!nmea.canExecuteTackManeuver || nmea.isTackInProgress)

                    if let reason = tackDisabledReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            })
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
        @Bindable var nmea = nmea
        VStack(alignment: .leading, spacing: 0) {
            ControlSliderView(
                value: $nmea.speed,
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
                value: $nmea.depth,
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
                value: $nmea.seaTemp,
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
            ControlSliderView(
                value: $nmea.heading,
                title: "Heading",
                unit: "°",
                precision: 0,
                sliderRange: SimulatedValueType.magneticCompass.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasCompass,
                disabledReason: !nmea.sensorToggles.hasCompass ? "Enable the Magnetic Compass in Configuration to control magnetic heading." : nil,
                supportingNote: nmea.sensorToggles.hasGyro ? "Gyro heading is the primary source while the gyro is enabled." : "Magnetic heading is the active heading source because no gyro is enabled.",
                wrapsCircularDegrees: true
            )
            RailDivider()
            ControlSliderView(
                value: $nmea.gyroHeading,
                title: "Gyro Heading",
                unit: "°",
                precision: 0,
                sliderRange: SimulatedValueType.gyroCompass.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasGyro,
                disabledReason: !nmea.sensorToggles.hasGyro ? "Enable the Gyro Compass in Configuration to control true heading." : nil,
                supportingNote: nmea.sensorToggles.hasGyro ? "Gyro heading is the preferred heading source for derived calculations and true-heading sentences." : nil,
                wrapsCircularDegrees: true
            )
        }
    }
}

struct EnvironmentControls: View {
    @Bindable var nmea: NMEASimulator

    var body: some View {
        @Bindable var nmea = nmea

        VStack(alignment: .leading, spacing: 0) {
            ControlSliderView(
                value: $nmea.airTemp,
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
                value: $nmea.humidity,
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
                value: $nmea.barometer,
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
struct BoatSetupDetailView: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 3 * UIConstants.spacing) {
                    Text("Boat")
                        .font(.largeTitle)
                    Text("Choose the polar profile, speed model, and execute a timed tack onto the opposite close-hauled heading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GroupBox(label: Label("Profile & maneuver", systemImage: "sailboat")) {
                        BoatControls(nmea: nmeaManager, chrome: .setupForm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Preview
#Preview {
    LeftControlsPanel(nmea: NMEASimulator())
        .environment(NMEASimulator())
        .frame(width: 340, height: 800)
}
