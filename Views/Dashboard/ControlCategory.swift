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
    case wind = "Wind", hydro = "Hydro", heading = "Heading"
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
                precision: 0,
                sliderRange: SimulatedValueType.windDirection.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasAnemometer,
                disabledReason: !nmea.sensorToggles.hasAnemometer ? "Enable the Anemometer in Configuration to control wind." : nil
            )
            RailDivider()
            ControlSliderView(
                value: $nmea.tws,
                title: "True Wind Speed",
                precision: 1,
                sliderRange: SimulatedValueType.windSpeed.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasAnemometer,
                disabledReason: !nmea.sensorToggles.hasAnemometer ? "Enable the Anemometer in Configuration to control wind." : nil
            )
        }
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
                precision: 1,
                sliderRange: SimulatedValueType.speedLog.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasSpeedLog,
                disabledReason: !nmea.sensorToggles.hasSpeedLog ? "Enable the Speed Log in Configuration to control water speed." : nil
            )
            RailDivider()
            ControlSliderView(
                value: $nmea.depth,
                title: "Depth",
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
                precision: 1,
                sliderRange: SimulatedValueType.seaTemp.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasWaterTempSensor,
                disabledReason: !nmea.sensorToggles.hasWaterTempSensor ? "Enable the Water Temperature sensor in Configuration to control sea temperature." : nil
            )
        }
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
                precision: 0,
                sliderRange: SimulatedValueType.magneticCompass.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasCompass,
                disabledReason: !nmea.sensorToggles.hasCompass ? "Enable the Magnetic Compass in Configuration to control magnetic heading." : nil,
                supportingNote: nmea.sensorToggles.hasGyro ? "Gyro heading is the primary source while the gyro is enabled." : "Magnetic heading is the active heading source because no gyro is enabled."
            )
            RailDivider()
            ControlSliderView(
                value: $nmea.gyroHeading,
                title: "Gyro Heading",
                precision: 0,
                sliderRange: SimulatedValueType.gyroCompass.defaultRange,
                onChange: nmea.persistLiveSettings,
                isDisabled: !nmea.sensorToggles.hasGyro,
                disabledReason: !nmea.sensorToggles.hasGyro ? "Enable the Gyro Compass in Configuration to control true heading." : nil,
                supportingNote: nmea.sensorToggles.hasGyro ? "Gyro heading is the preferred heading source for derived calculations and true-heading sentences." : nil
            )
        }
    }
}

// MARK: - Preview
#Preview {
    LeftControlsPanel(nmea: NMEASimulator())
        .environment(NMEASimulator())
        .frame(width: 340, height: 800)
}
