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
    case hydro = "Hydro"
    case heading = "Heading"
    case environment = "Environment"
}

// MARK: - Main Left Panel
struct LeftControlsPanel: View {
    @Bindable var nmea: NMEASimulator
    @State private var category: ControlCategory = .wind

    var body: some View {
        VStack(alignment: .leading, spacing: AppChrome.railSectionSpacing) {
            RailSection("Live Controls", subtitle: "Adjust installed instruments directly from the dashboard. Disabled controls reflect missing sensors.") {
                Picker("", selection: $category) {
                    ForEach(ControlCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch category {
                    case .wind: WindControls(nmea: nmea)
                    case .hydro: HydroControls(nmea: nmea)
                    case .heading: HeadingControls(nmea: nmea)
                    case .environment: EnvironmentControls(nmea: nmea)
                    }
                }
                .padding(.top, 2)
            }
            .scrollIndicators(.never)
        }
        .padding(AppChrome.railPadding)
        .frame(minWidth: 300, maxHeight: .infinity)
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

// MARK: - Hydro Controls
struct HydroControls: View {
    @Bindable var nmea: NMEASimulator
    var body: some View {
        @Bindable var nmea = nmea
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Boat Speed Model")
                    .font(.headline)

                Picker("Boat Speed Model", selection: $nmea.boatSpeedMode) {
                    ForEach(BoatSpeedMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if nmea.boatSpeedMode == .estimated {
                    Picker("Boat Profile", selection: $nmea.boatProfile) {
                        ForEach(BoatProfile.allCases) { profile in
                            Text(profile.shortName).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(nmea.boatProfile.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)

            RailDivider()

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

// MARK: - Preview
#Preview {
    LeftControlsPanel(nmea: NMEASimulator())
        .environment(NMEASimulator())
        .frame(width: 340, height: 800)
}
