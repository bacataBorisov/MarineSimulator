import SwiftUI

/// Scrollable page shell used by Connection and the other sidebar panels.
struct PageContainer<Content: View>: View {
    var maxWidth: CGFloat = PageChrome.maxWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .pageContentFrame(maxWidth: maxWidth)
        }
    }
}

extension View {
    func pageContentFrame(maxWidth: CGFloat = PageChrome.maxWidth) -> some View {
        self
            .padding(PageChrome.padding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Transport styling

extension TransportStatusLevel {
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .connected: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "questionmark.circle"
        case .connected: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

enum PrimaryOutputSummary {
    static func label(for simulator: NMEASimulator) -> String {
        guard let primary = simulator.outputEndpoints.first else {
            return "Primary: not configured"
        }
        let name = primary.name.isEmpty ? "Primary" : primary.name
        if !primary.isEnabled {
            return "\(name): off"
        }
        let transport = primary.transport.rawValue.uppercased()
        if primary.transport == .udp, primary.isBroadcast {
            return "\(name): UDP broadcast :\(primary.port)"
        }
        return "\(name): \(transport) \(primary.host):\(primary.port)"
    }
}

// MARK: - Connection health banner

struct ConnectionHealthBanner: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        Group {
            if nmeaManager.isTransmitting {
                if let status = nmeaManager.latestTransportStatus {
                    Label(status.message, systemImage: status.level.systemImage)
                        .foregroundStyle(status.level.color)
                } else {
                    Label("Transmitting", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                }
            } else if let status = nmeaManager.latestTransportStatus, status.level != .idle {
                Label(status.message, systemImage: status.level.systemImage)
                    .foregroundStyle(status.level.color)
            } else {
                Label("Not sending — press Start (⌘R)", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Endpoint editor

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EndpointEditorView: View {
    @Bindable var nmeaManager: NMEASimulator
    @Binding var endpoint: OutputEndpoint
    let isPrimary: Bool

    var body: some View {
        let status = nmeaManager.transportStatus(for: endpoint.id)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(endpoint.name.isEmpty ? (isPrimary ? "Primary Output" : "Untitled") : endpoint.name)
                    .font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $endpoint.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                if !isPrimary {
                    Button(role: .destructive) {
                        nmeaManager.removeOutputEndpoint(id: endpoint.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if !endpoint.isEnabled {
                Label("Disabled — not sending", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status {
                Label(status.message, systemImage: status.level.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.level.color)
            } else {
                Label("No transport activity yet", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            fieldRow("Name") {
                TextField("Output Name", text: $endpoint.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            fieldRow("Transport") {
                Picker("Transport", selection: $endpoint.transport) {
                    ForEach(NetworkTransport.allCases) { transport in
                        Text(transport.rawValue.uppercased()).tag(transport)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .onChange(of: endpoint.transport) { _, newTransport in
                    if newTransport == .tcp { endpoint.isBroadcast = false }
                }
            }

            if endpoint.transport == .udp {
                Toggle("Broadcast to subnet", isOn: $endpoint.isBroadcast)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
            }

            fieldRow("Host") {
                TextField("Host", text: Binding(
                    get: { endpoint.effectiveHost },
                    set: { if !endpoint.isBroadcast { endpoint.host = $0 } }
                ))
                .disabled(endpoint.transport == .udp && endpoint.isBroadcast)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            }

            fieldRow("Port") {
                TextField("Port", value: $endpoint.port, formatter: FormatKit.plainNumberFormatter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
            }

            if isPrimary {
                fieldRow("Talker ID") {
                    TextField("Talker ID", text: $nmeaManager.talkerID)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                        .disabled(nmeaManager.selectedProfile != .custom)
                }

                Text("3 characters, e.g. II or GP. Per-sentence talkers follow the hardware profile unless Custom.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sensor grid

struct SensorToggleGrid: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        // Adaptive columns avoid ViewThatFits clipping inside Form scroll content.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
            spacing: 12
        ) {
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
                    ViewKit.ToggleRowWithInfo(toggles[i].0, isOn: toggles[i].1)
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
        case .idle: return .secondary
        case .fetching: return .blue
        case .ready: return .green
        case .failed: return .orange
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
                        Text(event.timestamp, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(event.message)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.dropRate)
                    Text("Delay Rate")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.delayRate)
                }
                GridRow {
                    Text("Checksum Corruption")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.checksumCorruptionRate)
                    Text("Invalid Data Rate")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.invalidDataRate)
                }
                GridRow {
                    Text("Max Delay Cycles")
                    Stepper(value: $nmeaManager.faultInjection.maximumDelayCycles, in: 1...5) {
                        Text("\(nmeaManager.faultInjection.maximumDelayCycles)")
                            .monospacedDigit()
                    }
                    .disabled(!nmeaManager.faultInjection.isEnabled)
                }
            }
            .disabled(!nmeaManager.faultInjection.isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FaultInjectionPercentageStepper: View {
    @Binding var value: Double

    var body: some View {
        Stepper(value: $value, in: 0...0.9, step: 0.05) {
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OpenSimulationSensorsButton: View {
    @Environment(\.sidebarNavigation) private var sidebarNavigation

    var body: some View {
        Button("Open Simulation → Sensors") {
            sidebarNavigation?.select(.simulation)
        }
        .buttonStyle(.link)
        .font(.caption2)
    }
}
