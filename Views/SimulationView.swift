import SwiftUI

struct SimulationView: View {
    @AppStorage("configuration.show_advanced") private var showAdvancedControls: Bool = false
    @Bindable var nmeaManager: NMEASimulator
    @State private var rateModeNotice: String?

    var body: some View {
        PageContainer {
            Form {
                Section("Hardware Profile") {
                    Text("Match real instrument clusters for realistic NMEA timing, talker IDs, and sentence sets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Hardware Profile", selection: Binding(
                        get: { nmeaManager.selectedProfile },
                        set: { nmeaManager.applyHardwareProfile($0) }
                    )) {
                        ForEach(HardwareProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(nmeaManager.selectedProfile.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Sentence Update Rates") {
                    Text("Realistic mode uses hardware-accurate per-sentence intervals. Custom mode enables per-sentence editing in each instrument panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Rate Mode", selection: $nmeaManager.sentenceRateMode) {
                        ForEach(SentenceRateMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: nmeaManager.sentenceRateMode) { oldMode, newMode in
                        if newMode == .realistic {
                            let prior = nmeaManager.selectedProfile
                            if prior == .custom {
                                nmeaManager.selectedProfile = .bngTriton2
                                rateModeNotice = "Realistic mode uses B&G Triton2 intervals (profile was Custom)."
                            } else {
                                rateModeNotice = "Per-sentence intervals follow \(prior.rawValue)."
                            }
                        } else {
                            rateModeNotice = "Edit intervals in Wind, Heading, Hydro, and GPS panels."
                        }
                        _ = oldMode
                    }

                    if let rateModeNotice {
                        Text(rateModeNotice)
                            .font(.caption2)
                            .foregroundStyle(nmeaManager.sentenceRateMode == .custom ? AppColors.warning : .secondary)
                    } else if nmeaManager.sentenceRateMode == .realistic {
                        Text("Per-sentence intervals follow the selected hardware profile defaults.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Edit intervals in Wind, Heading, Hydro, and GPS panels.")
                            .font(.caption2)
                            .foregroundStyle(AppColors.warning)
                    }
                }

                Section("Test Presets") {
                    Text("Apply a named baseline to wind, speed, heading, and GPS motion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Preset", selection: Binding(
                        get: { nmeaManager.selectedPreset ?? .lightWeather },
                        set: { newPreset in
                            nmeaManager.selectedPreset = newPreset
                            nmeaManager.applyPreset(newPreset)
                        }
                    )) {
                        ForEach(SimulationPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(nmeaManager.weatherSourceMode == .liveWeather)

                    Text((nmeaManager.selectedPreset ?? .lightWeather).summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if nmeaManager.weatherSourceMode == .liveWeather {
                        Text("Presets are disabled while Live Weather mode is active.")
                            .font(.caption2)
                            .foregroundStyle(AppColors.warning)
                    }
                }

                Section("Weather Source") {
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
                        LabeledContent("Refresh Every") {
                            Stepper(value: $nmeaManager.liveWeatherSettings.refreshIntervalMinutes, in: 1...60, step: 1) {
                                Text("\(nmeaManager.liveWeatherSettings.refreshIntervalMinutes) min")
                                    .monospacedDigit()
                            }
                        }
                        LabeledContent("Refresh After") {
                            Stepper(value: $nmeaManager.liveWeatherSettings.minimumRefreshDistanceNM, in: 1...30, step: 1) {
                                Text("\(nmeaManager.liveWeatherSettings.minimumRefreshDistanceNM.formatted(.number.precision(.fractionLength(0)))) nm")
                                    .monospacedDigit()
                            }
                        }

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: WeatherStatusStyle.systemImage(for: nmeaManager.liveWeatherStatus.state))
                            Text(nmeaManager.liveWeatherStatus.message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption)
                        .foregroundStyle(WeatherStatusStyle.color(for: nmeaManager.liveWeatherStatus.state))

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

                        DisclosureGroup("Last fetch details") {
                            if let latestLiveWeather = nmeaManager.latestLiveWeather {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Provider: \(latestLiveWeather.sourceName)")
                                    if let marineSourceName = latestLiveWeather.marineSourceName {
                                        Text("Marine: \(marineSourceName)")
                                    }
                                    Text("Wind: \(WeatherStatusStyle.weatherValue(latestLiveWeather.trueWindDirection, unit: "°")) / \(WeatherStatusStyle.weatherValue(latestLiveWeather.trueWindSpeedKnots, unit: "kn"))")
                                    Text("Gust: \(WeatherStatusStyle.weatherValue(latestLiveWeather.windGustSpeedKnots, unit: "kn"))")
                                    Text("Sea Temp: \(WeatherStatusStyle.weatherValue(latestLiveWeather.seaSurfaceTemperatureCelsius, unit: "°C"))")
                                    Text("Air Temp: \(WeatherStatusStyle.weatherValue(latestLiveWeather.airTemperatureCelsius, unit: "°C"))")
                                    Text("Humidity: \(WeatherStatusStyle.weatherValue(latestLiveWeather.relativeHumidityPercent, unit: "%"))")
                                    Text("Pressure: \(WeatherStatusStyle.weatherValue(latestLiveWeather.airPressureHectopascals, unit: "hPa"))")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else {
                                Text("No live weather snapshot yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastUpdated = nmeaManager.liveWeatherStatus.lastUpdated {
                                Text("Last Update: \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Onboard Sensors") {
                    SensorToggleGrid(nmeaManager: nmeaManager)
                }

                Section {
                    Toggle("Show Advanced Simulation Controls", isOn: $showAdvancedControls)
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                }

                if showAdvancedControls {
                    Section("Advanced Simulation Controls") {
                        Text("Use these only when debugging compatibility, fault tolerance, or protocol edge cases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SensorToggleGroup(title: "Satellite & Communication", icon: "antenna.radiowaves.left.and.right.circle", toggles: [
                            ("GNSS Receiver", $nmeaManager.sensorToggles.shouldSendGNSS),
                            ("DSC Radio / MMSI", $nmeaManager.sensorToggles.shouldSendDSC),
                        ])

                        RecentTransportEventsSection(nmeaManager: nmeaManager)
                        FaultInjectionSection(nmeaManager: nmeaManager)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    SimulationView(nmeaManager: NMEASimulator())
        .frame(width: 820, height: 720)
}
