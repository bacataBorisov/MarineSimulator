import SwiftUI

struct ConfigurationView: View {

    @AppStorage("configuration.show_advanced") private var showAdvancedControls: Bool = false
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .center, spacing: 3 * UIConstants.spacing) {
                    GroupBox(label: Label("Network Settings", systemImage: "network")) {
                        Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("IP")
                                TextField("IP Address", text: $nmeaManager.ip)
                                    .gridColumnAlignment(.leading)
                                Text("Port")
                                TextField("Port", value: $nmeaManager.port, formatter: FormatKit.plainNumberFormatter)
                                Text("Talker ID")
                                TextField("Talker ID", text: $nmeaManager.talkerID)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)

                    GroupBox(label: Label("Core Setup", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: UIConstants.spacing) {
                            Text("Keep the setup small: choose where to send data, how often to send it, and which onboard sensors should exist. Advanced testing tools stay hidden until you need them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Show Advanced Simulation Controls", isOn: $showAdvancedControls)
                                .toggleStyle(.switch)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    GroupBox(label: Label("Test Presets", systemImage: "cloud.sun")) {
                        VStack(alignment: .leading, spacing: UIConstants.spacing) {
                            Text("Apply a named baseline to wind, speed, heading, and GPS motion so repeated manual testing starts from a known setup.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: UIConstants.spacing * 2) {
                                Picker("Preset", selection: Binding(
                                    get: { nmeaManager.selectedPreset ?? .lightWeather },
                                    set: { nmeaManager.selectedPreset = $0 }
                                )) {
                                    ForEach(SimulationPreset.allCases) { preset in
                                        Text(preset.displayName).tag(preset)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Button {
                                    nmeaManager.applyPreset(nmeaManager.selectedPreset ?? .lightWeather)
                                } label: {
                                    Label("Apply Preset", systemImage: "sparkles")
                                }
                            }

                            Text((nmeaManager.selectedPreset ?? .lightWeather).summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    GroupBox(label: Label("Output Endpoints", systemImage: "point.3.filled.connected.trianglepath.dotted")) {
                        VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
                            Text("Primary output stays synced with the IP and port fields above. Additional outputs can be enabled for multi-destination testing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach($nmeaManager.outputEndpoints) { $endpoint in
                                endpointEditor(endpoint: $endpoint)
                            }

                            HStack {
                                Spacer()
                                Button {
                                    nmeaManager.addOutputEndpoint()
                                } label: {
                                    Label("Add Output", systemImage: "plus")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    GroupBox(label: Label("Transmission", systemImage: "antenna.radiowaves.left.and.right")) {
                        Grid(horizontalSpacing: 3 * UIConstants.spacing, verticalSpacing: 3 * UIConstants.spacing) {
                            GridRow {
                                Toggle("Enable Timer", isOn: $nmeaManager.isTimerSelected)
                                    .toggleStyle(.switch)
                                    .gridColumnAlignment(.leading)
                                Text("Send Interval (s)")
                                Stepper(value: $nmeaManager.interval, in: 0.1...10, step: 0.1) {
                                    Text(String(format: "%.1f", nmeaManager.interval))
                                        .monospacedDigit()
                                }
                                .disabled(!nmeaManager.isTimerSelected)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Text(nmeaManager.isTimerSelected ? "Continuous timer mode is active." : "Timer disabled: Start sends one burst only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    HStack(alignment: .top, spacing: UIConstants.spacing) {
                        sensorBox(
                            title: "Navigation Instruments",
                            icon: "safari",
                            toggles: [
                                ("Anemometer", $nmeaManager.sensorToggles.hasAnemometer),
                                ("Magnetic Compass", $nmeaManager.sensorToggles.hasCompass),
                                ("Gyro Compass", $nmeaManager.sensorToggles.hasGyro)
                            ]
                        )

                        sensorBox(
                            title: "Hydro Sensors",
                            icon: "drop.triangle",
                            toggles: [
                                ("Echo Sounder", $nmeaManager.sensorToggles.hasEchoSounder),
                                ("Speed Log", $nmeaManager.sensorToggles.hasSpeedLog),
                                ("Water Temperature", $nmeaManager.sensorToggles.hasWaterTempSensor)
                            ]
                        )

                        sensorBox(
                            title:"Environmental Sensors",
                            icon: "thermometer.sun.circle",
                            toggles: [
                                ("Air Temperature", $nmeaManager.sensorToggles.hasAirTempSensor),
                                ("Humidity", $nmeaManager.sensorToggles.hasHumidtySensor),
                                ("Barometer", $nmeaManager.sensorToggles.hasBarometer)
                            ]
                        )
                        
                    }
                    .padding(.horizontal)


                    HStack(alignment: .top, spacing: UIConstants.spacing) {
                        sensorBox(
                            title: "Positioning",
                            icon: "location",
                            toggles: [
                                ("GPS", $nmeaManager.sensorToggles.hasGPS),
                                ("AIS", $nmeaManager.sensorToggles.hasAIS)
                            ]
                        )
                    }
                    .padding(.horizontal)

                    if showAdvancedControls {
                        GroupBox(label: Label("Advanced Simulation Controls", systemImage: "wrench.and.screwdriver")) {
                            VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
                                Text("Use these only when you are debugging compatibility, fault tolerance, or protocol edge cases. Most realistic runs should not need them.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                sensorBox(
                                    title: "Satellite & Communication",
                                    icon: "antenna.radiowaves.left.and.right.circle",
                                    toggles: [
                                        ("GNSS Receiver", $nmeaManager.sensorToggles.shouldSendGNSS),
                                        ("DSC Radio / MMSI", $nmeaManager.sensorToggles.shouldSendDSC)
                                    ]
                                )

                                Divider()

                                recentTransportEventsSection

                                Divider()

                                faultInjectionSection
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.vertical
                )
            }
        }
    }

    // MARK: - Sensor Box View
    @ViewBuilder
    private func sensorBox(title: String, icon: String, toggles: [(String, Binding<Bool>)]) -> some View {
        GroupBox(label: Label(title, systemImage: icon)) {
            VStack(spacing: UIConstants.spacing * 2) {
                ForEach(toggles.indices, id: \.self) { i in
                    ViewKit.ToggleRowWithInfo(
                        toggles[i].0,
                        isOn: toggles[i].1
                        
                        //MARK: - I need to see if it is useful!!
                        //showInfo: .constant(false) // or bind to a real state if needed
                        //infoView: { AnyView(EmptyView()) } // you can provide real help views here
                    )
                }
            }
            .toggleStyle(.switch)
            .padding()
        }
    }

    @ViewBuilder
    private var recentTransportEventsSection: some View {
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

    @ViewBuilder
    private var faultInjectionSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
            Label("Fault Injection", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.headline)

            Toggle("Enable Fault Injection", isOn: $nmeaManager.faultInjection.isEnabled)
                .toggleStyle(.switch)

            Text("Inject controlled faults to test how receivers handle bad or imperfect NMEA traffic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(horizontalSpacing: 16, verticalSpacing: UIConstants.spacing) {
                GridRow {
                    Text("Drop Rate")
                    percentageStepper($nmeaManager.faultInjection.dropRate)
                    Text("Delay Rate")
                    percentageStepper($nmeaManager.faultInjection.delayRate)
                }

                GridRow {
                    Text("Checksum Corruption")
                    percentageStepper($nmeaManager.faultInjection.checksumCorruptionRate)
                    Text("Invalid Data Rate")
                    percentageStepper($nmeaManager.faultInjection.invalidDataRate)
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

    @ViewBuilder
    private func endpointEditor(endpoint: Binding<OutputEndpoint>) -> some View {
        let isPrimary = endpoint.wrappedValue.id == nmeaManager.outputEndpoints.first?.id
        let status = nmeaManager.transportStatus(for: endpoint.wrappedValue.id)

        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            HStack {
                Text(isPrimary ? "Primary Output" : endpoint.wrappedValue.name)
                    .font(.headline)

                Spacer()

                Toggle("Enabled", isOn: endpoint.isEnabled)
                    .toggleStyle(.switch)
                    .disabled(isPrimary)

                if !isPrimary {
                    Button(role: .destructive) {
                        nmeaManager.removeOutputEndpoint(id: endpoint.wrappedValue.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let status {
                Label(status.message, systemImage: status.level.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.level.color)
            } else {
                Label("No transport activity yet", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(horizontalSpacing: UIConstants.spacing * 2, verticalSpacing: UIConstants.spacing) {
                GridRow {
                    Text("Name")
                    TextField("Output Name", text: endpoint.name)
                    Text("Transport")
                    Picker("Transport", selection: endpoint.transport) {
                        ForEach(NetworkTransport.allCases) { transport in
                            Text(transport.rawValue.uppercased()).tag(transport)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Host")
                    TextField("Host", text: endpoint.host)
                    Text("Port")
                    TextField("Port", value: endpoint.port, formatter: FormatKit.plainNumberFormatter)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func percentageStepper(_ value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...0.9, step: 0.05) {
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension TransportStatusLevel {
    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .connected:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "questionmark.circle"
        case .connected:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }
}

#Preview {
    ConfigurationView(nmeaManager: NMEASimulator())
        .frame(width: 900, height: 600)
}
