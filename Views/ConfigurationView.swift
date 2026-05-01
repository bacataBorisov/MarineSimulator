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
                                // Always a TextField — disabled + shows broadcast address when broadcast is on.
                                // This keeps the row height stable; only the toggle moves.
                                TextField("IP Address", text: Binding(
                                    get: { nmeaManager.isBroadcast ? "255.255.255.255" : nmeaManager.ip },
                                    set: { if !nmeaManager.isBroadcast { nmeaManager.ip = $0 } }
                                ))
                                .disabled(nmeaManager.isBroadcast)
                                .foregroundStyle(nmeaManager.isBroadcast ? Color.secondary : Color.primary)
                                .gridColumnAlignment(.leading)
                                Text("Port")
                                TextField("Port", value: $nmeaManager.port, formatter: FormatKit.plainNumberFormatter)
                                Text("Talker ID")
                                TextField("Talker ID", text: $nmeaManager.talkerID)
                            }
                            GridRow {
                                Text("Broadcast")
                                Toggle("Broadcast", isOn: $nmeaManager.isBroadcast)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .gridCellColumns(5)
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
                                .disabled(nmeaManager.weatherSourceMode == .liveWeather)

                                Button {
                                    nmeaManager.applyPreset(nmeaManager.selectedPreset ?? .lightWeather)
                                } label: {
                                    Label("Apply Preset", systemImage: "sparkles")
                                }
                                .disabled(nmeaManager.weatherSourceMode == .liveWeather)
                            }

                            Text((nmeaManager.selectedPreset ?? .lightWeather).summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if nmeaManager.weatherSourceMode == .liveWeather {
                                Text("Presets are disabled while Live Weather mode is active because weather-related values are driven from GPS-based provider data.")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.warning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    GroupBox(label: Label("Weather Source", systemImage: "cloud.sun.rain")) {
                        VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
                            Text("Use manual controls by default, or pull live wind and sea temperature from the boat's current GPS position.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Weather Source", selection: $nmeaManager.weatherSourceMode) {
                                ForEach(WeatherSourceMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if nmeaManager.weatherSourceMode == .liveWeather {
                                Grid(horizontalSpacing: 16, verticalSpacing: UIConstants.spacing) {
                                    GridRow {
                                        Text("Refresh Every")
                                        Stepper(value: $nmeaManager.liveWeatherSettings.refreshIntervalMinutes, in: 1...60, step: 1) {
                                            Text("\(nmeaManager.liveWeatherSettings.refreshIntervalMinutes) min")
                                                .monospacedDigit()
                                        }
                                        Text("Refresh After")
                                        Stepper(value: $nmeaManager.liveWeatherSettings.minimumRefreshDistanceNM, in: 1...30, step: 1) {
                                            Text("\(nmeaManager.liveWeatherSettings.minimumRefreshDistanceNM.formatted(.number.precision(.fractionLength(0)))) nm")
                                                .monospacedDigit()
                                        }
                                    }
                                }

                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: weatherStatusSystemImage)
                                    Text(nmeaManager.liveWeatherStatus.message)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.caption)
                                .foregroundStyle(weatherStatusColor)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if let latestLiveWeather = nmeaManager.latestLiveWeather {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Provider: \(latestLiveWeather.sourceName)")
                                        if let marineSourceName = latestLiveWeather.marineSourceName {
                                            Text("Marine: \(marineSourceName)")
                                        }
                                        Text("Wind: \(weatherValue(latestLiveWeather.trueWindDirection, unit: "°")) / \(weatherValue(latestLiveWeather.trueWindSpeedKnots, unit: "kn"))")
                                        Text("Gust: \(weatherValue(latestLiveWeather.windGustSpeedKnots, unit: "kn"))")
                                        Text("Sea Temp: \(weatherValue(latestLiveWeather.seaSurfaceTemperatureCelsius, unit: "°C"))")
                                        Text("Air Temp: \(weatherValue(latestLiveWeather.airTemperatureCelsius, unit: "°C"))")
                                        Text("Humidity: \(weatherValue(latestLiveWeather.relativeHumidityPercent, unit: "%"))")
                                        Text("Pressure: \(weatherValue(latestLiveWeather.airPressureHectopascals, unit: "hPa"))")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                if let lastUpdated = nmeaManager.liveWeatherStatus.lastUpdated {
                                    Text("Last Update: \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Button {
                                        nmeaManager.refreshLiveWeather(force: true)
                                    } label: {
                                        Label("Refresh Weather", systemImage: "arrow.clockwise")
                                    }
                                    .disabled(!nmeaManager.sensorToggles.hasGPS || nmeaManager.liveWeatherStatus.state == .fetching)

                                    if !nmeaManager.sensorToggles.hasGPS {
                                        Text("Enable GPS to fetch live weather.")
                                            .font(.caption2)
                                            .foregroundStyle(AppColors.warning)
                                    }
                                }
                            }
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
                                ("GPS", $nmeaManager.sensorToggles.hasGPS)
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

                if endpoint.wrappedValue.transport == .udp {
                    // Broadcast toggle + Port always on the same row.
                    GridRow {
                        Text("Broadcast")
                        Toggle("Broadcast", isOn: endpoint.isBroadcast)
                            .labelsHidden()
                            .toggleStyle(.switch)
                        Text("Port")
                        TextField("Port", value: endpoint.port, formatter: FormatKit.plainNumberFormatter)
                    }
                    // Host row is always present so the card never resizes when toggling.
                    // When broadcast is on it shows the effective address, disabled + grayed.
                    GridRow {
                        Text("Host")
                        TextField("Host", text: Binding(
                            get: { endpoint.wrappedValue.effectiveHost },
                            set: { if !endpoint.wrappedValue.isBroadcast { endpoint.wrappedValue.host = $0 } }
                        ))
                        .disabled(endpoint.wrappedValue.isBroadcast)
                        .foregroundStyle(endpoint.wrappedValue.isBroadcast ? Color.secondary : Color.primary)
                        .gridCellColumns(3)
                    }
                } else {
                    GridRow {
                        Text("Host")
                        TextField("Host", text: endpoint.host)
                        Text("Port")
                        TextField("Port", value: endpoint.port, formatter: FormatKit.plainNumberFormatter)
                    }
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

    private var weatherStatusColor: Color {
        switch nmeaManager.liveWeatherStatus.state {
        case .idle:
            return .secondary
        case .fetching:
            return .blue
        case .ready:
            return .green
        case .failed:
            return .orange
        }
    }

    private var weatherStatusSystemImage: String {
        switch nmeaManager.liveWeatherStatus.state {
        case .idle:
            return "cloud"
        case .fetching:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func weatherValue(_ value: Double?, unit: String) -> String {
        guard let value else {
            return "--"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
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
