import SwiftUI

struct SimulationView: View {
    @Bindable var nmeaManager: NMEASimulator
    @State private var rateModeNotice: String?

    var body: some View {
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.record(.simulation)
        #endif
        PageContainer(maxWidth: ResponsiveLayout.adaptivePageMaxWidth) {
            SetupColumns {
                hardwareProfile
                sentenceRates
                testPresets
                weatherSource
                onboardSensors
                advancedControls
            } wide: {
                HStack(alignment: .top, spacing: ResponsiveLayout.configurationGutter) {
                    VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
                        hardwareProfile
                        sentenceRates
                    }
                    .frame(maxWidth: ResponsiveLayout.configurationCardMaximum, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
                        testPresets
                        weatherSource
                    }
                    .frame(maxWidth: ResponsiveLayout.configurationCardMaximum, alignment: .topLeading)
                }
                onboardSensors
                advancedControls
            }
            .background(alignment: .topLeading) {
                RetainedDestinationMarker(page: .simulation)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hardwareProfile: some View {
        SettingsCard(title: "Hardware Profile", accessibilityID: SetupSection.hardwareProfile.rawValue) {
                    Text("Match real instrument clusters for realistic NMEA timing, talker IDs, and sentence sets.")
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(DesignToken.Status.neutral)

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
                        .font(DesignToken.Typography.help)
                        .foregroundStyle(DesignToken.Status.neutral)
                }

    }

    private var sentenceRates: some View {
        SettingsCard(title: "Sentence Update Rates", accessibilityID: SetupSection.sentenceUpdateRates.rawValue) {
                    Text("Realistic mode uses hardware-accurate per-sentence intervals. Custom mode enables per-sentence editing in each instrument panel.")
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(DesignToken.Status.neutral)

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
                            .font(DesignToken.Typography.help)
                            .foregroundStyle(nmeaManager.sentenceRateMode == .custom ? DesignToken.Status.warning : DesignToken.Status.neutral)
                    } else if nmeaManager.sentenceRateMode == .realistic {
                        Text("Per-sentence intervals follow the selected hardware profile defaults.")
                            .font(DesignToken.Typography.help)
                            .foregroundStyle(DesignToken.Status.neutral)
                    } else {
                        Text("Edit intervals in Wind, Heading, Hydro, and GPS panels.")
                            .font(DesignToken.Typography.help)
                            .foregroundStyle(DesignToken.Status.warning)
                    }
                }

    }

    private var testPresets: some View {
        SettingsCard(title: "Test Presets", accessibilityID: SetupSection.testPresets.rawValue) {
                    Text("Apply a named baseline to wind, speed, heading, and GPS motion.")
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(DesignToken.Status.neutral)

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
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(DesignToken.Status.neutral)

                    if nmeaManager.weatherSourceMode == .liveWeather {
                        Text("Presets are disabled while Live Weather mode is active.")
                            .font(DesignToken.Typography.help)
                            .foregroundStyle(DesignToken.Status.warning)
                    }
                }

    }

    private var weatherSource: some View {
        SettingsCard(title: "Weather Source", accessibilityID: SetupSection.weatherSource.rawValue) {
                    Text("Use manual controls by default, or pull live wind and sea temperature from the boat's current GPS position.")
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(DesignToken.Status.neutral)

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

                        HStack(alignment: .top, spacing: DesignToken.Spacing.related) {
                            Image(systemName: WeatherStatusStyle.systemImage(for: nmeaManager.liveWeatherStatus.state))
                            Text(nmeaManager.liveWeatherStatus.message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(DesignToken.Typography.supporting)
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
                                    .font(DesignToken.Typography.help)
                                    .foregroundStyle(DesignToken.Status.warning)
                            }
                        }

                        DisclosureGroup("Last fetch details") {
                            if let latestLiveWeather = nmeaManager.latestLiveWeather {
                                VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
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
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.neutral)
                            } else {
                                Text("No live weather snapshot yet.")
                                    .font(DesignToken.Typography.supporting)
                                    .foregroundStyle(DesignToken.Status.neutral)
                            }

                            if let lastUpdated = nmeaManager.liveWeatherStatus.lastUpdated {
                                Text("Last Update: \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(DesignToken.Typography.help)
                                    .foregroundStyle(DesignToken.Status.neutral)
                            }
                        }
                    }
                }
    }

    private var onboardSensors: some View {
        SettingsCard(title: "Onboard Sensors", accessibilityID: SetupSection.onboardSensors.rawValue) {
            SensorToggleGrid(nmeaManager: nmeaManager)
        }
    }

    private var advancedControls: some View {
        AdvancedSimulationControls(nmeaManager: nmeaManager)
            .accessibilityIdentifier(SetupSection.advancedControls.rawValue)
    }
}

/// Owns the advanced-controls setting so a selection write cannot refresh the rest of the form.
private struct AdvancedSimulationControls: View {
    @AppStorage("configuration.show_advanced") private var showAdvancedControls = false
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            SettingsCard {
                Toggle("Show Advanced Simulation Controls", isOn: $showAdvancedControls)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
            }

            if showAdvancedControls {
                advancedSection
            }
        }
    }

    private var advancedSection: some View {
        SettingsCard(title: "Advanced Simulation Controls") {
            Text("Use these only when debugging compatibility, fault tolerance, or protocol edge cases.")
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)

            Text("GNSS Receiver and DSC Radio are saved but do not emit sentences yet.")
                .font(DesignToken.Typography.help)
                .foregroundStyle(DesignToken.Status.neutral)

            SensorToggleGroup(title: "Satellite & Communication", icon: "antenna.radiowaves.left.and.right.circle", toggles: [
                ("GNSS Receiver", $nmeaManager.sensorToggles.shouldSendGNSS),
                ("DSC Radio / MMSI", $nmeaManager.sensorToggles.shouldSendDSC),
            ])
            .disabled(true)

            RecentTransportEventsSection(nmeaManager: nmeaManager)
            FaultInjectionSection(nmeaManager: nmeaManager)
        }
    }
}

#Preview {
    SimulationView(nmeaManager: NMEASimulator())
        .frame(width: 820, height: 720)
}
