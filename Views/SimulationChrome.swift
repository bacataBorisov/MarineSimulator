import SwiftUI

// MARK: - Sensor grid

struct SensorToggleGrid: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SensorToggleGroup(title: "Navigation Instruments", icon: "safari", toggles: [
                ("Anemometer", $nmeaManager.sensorToggles.hasAnemometer),
                ("Magnetic Compass", $nmeaManager.sensorToggles.hasCompass),
                ("Gyro Compass", $nmeaManager.sensorToggles.hasGyro),
            ])
            SensorToggleGroup(title: "Hydro Sensors", icon: "drop.triangle", toggles: [
                ("Echo Sounder", $nmeaManager.sensorToggles.hasEchoSounder),
                ("Speed Log", $nmeaManager.sensorToggles.hasSpeedLog),
                ("Water Temperature", $nmeaManager.sensorToggles.hasWaterTempSensor),
            ])
            SensorToggleGroup(title: "Environmental Sensors", icon: "thermometer.sun.circle", toggles: [
                ("Air Temperature", $nmeaManager.sensorToggles.hasAirTempSensor),
                ("Humidity", $nmeaManager.sensorToggles.hasHumidtySensor),
                ("Barometer", $nmeaManager.sensorToggles.hasBarometer),
            ])
            SensorToggleGroup(title: "Positioning", icon: "location", toggles: [
                ("GPS", $nmeaManager.sensorToggles.hasGPS),
            ])
        }
    }
}

struct SensorToggleGroup: View {
    let title: String
    let icon: String
    let toggles: [(String, Binding<Bool>)]

    var body: some View {
        GroupBox(label: Label(title, systemImage: icon)) {
            VStack(spacing: 12) {
                ForEach(toggles.indices, id: \.self) { i in
                    HStack {
                        Text(toggles[i].0)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(toggles[i].0)
                        Spacer()
                        Toggle("", isOn: toggles[i].1)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .accessibilityLabel(toggles[i].0)
                    }
                }
            }
            .padding(6)
        }
    }
}

// MARK: - Weather helpers

enum WeatherStatusStyle {
    static func color(for state: LiveWeatherStatusState) -> Color {
        switch state {
        case .idle: return DesignToken.Status.neutral
        case .fetching: return DesignToken.Status.info
        case .ready: return DesignToken.Status.success
        case .failed: return DesignToken.Status.warning
        }
    }

    static func systemImage(for state: LiveWeatherStatusState) -> String {
        switch state {
        case .idle: return "cloud"
        case .fetching: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    static func weatherValue(_ value: Double?, unit: String) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

// MARK: - Advanced sections

struct RecentTransportEventsSection: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            Label("Recent Transport Events", systemImage: "waveform.path.ecg")
                .font(.headline)

            if nmeaManager.transportHistory.isEmpty {
                Text("No transport events recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nmeaManager.transportHistory.suffix(8).reversed()) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label("", systemImage: event.level.systemImage)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(event.level.color)
                            .accessibilityHidden(true)
                        Text(event.timestamp, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(event.message)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FaultInjectionSection: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
            Label("Fault Injection", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.headline)

            Toggle("Enable Fault Injection", isOn: $nmeaManager.faultInjection.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.regular)

            Text("Inject controlled faults to test how receivers handle bad or imperfect NMEA traffic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(horizontalSpacing: 16, verticalSpacing: UIConstants.spacing) {
                GridRow {
                    Text("Drop Rate")
                    FaultInjectionPercentageStepper(title: "Drop rate", value: $nmeaManager.faultInjection.dropRate)
                    Text("Delay Rate")
                    FaultInjectionPercentageStepper(title: "Delay rate", value: $nmeaManager.faultInjection.delayRate)
                }
                GridRow {
                    Text("Checksum Corruption")
                    FaultInjectionPercentageStepper(title: "Checksum corruption rate", value: $nmeaManager.faultInjection.checksumCorruptionRate)
                    Text("Invalid Data Rate")
                    FaultInjectionPercentageStepper(title: "Invalid data rate", value: $nmeaManager.faultInjection.invalidDataRate)
                }
                GridRow {
                    Text("Max Delay Cycles")
                    Stepper(value: $nmeaManager.faultInjection.maximumDelayCycles, in: 1...5) {
                        Text("\(nmeaManager.faultInjection.maximumDelayCycles)")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Maximum delay cycles")
                    .disabled(!nmeaManager.faultInjection.isEnabled)
                }
            }
            .disabled(!nmeaManager.faultInjection.isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FaultInjectionPercentageStepper: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        Stepper(value: $value, in: 0...0.9, step: 0.05) {
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
        }
        .accessibilityLabel(title)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SensorEnablePrompt: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
            Text(message)
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.warning)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.link)
                .font(DesignToken.Typography.supporting)
        }
    }
}
