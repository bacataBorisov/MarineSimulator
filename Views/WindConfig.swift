// WindView.swift
// Extending with live-calculated AWA, AWS, AWD, TWA

import SwiftUI

struct WindConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @State var showMWV: Bool = false
    @State var showMWD: Bool = false
    @State var showVPW: Bool = false
    @State var showMDA: Bool = false
    @State var showXDR: Bool = false

    var body: some View {
        SentencePage {
            WindSentencesSection(
                shouldSendMWV: $nmeaManager.sentenceToggles.shouldSendMWV,
                shouldSendMWD: $nmeaManager.sentenceToggles.shouldSendMWD,
                shouldSendVPW: $nmeaManager.sentenceToggles.shouldSendVPW,
                showMWV: $showMWV,
                showMWD: $showMWD,
                showVPW: $showVPW,
                nmeaManager: nmeaManager
            )
            AtmosphericSentencesSection(
                shouldSendMDA: $nmeaManager.sentenceToggles.shouldSendMDA,
                shouldSendXDR: $nmeaManager.sentenceToggles.shouldSendXDR,
                showMDA: $showMDA,
                showXDR: $showXDR,
                nmeaManager: nmeaManager
            )
        } live: {
            ViewKit.displayLabel("TWD", value: nmeaManager.isTransmitting ? nmeaManager.twd.value : nil, precision: 0)
            ViewKit.displayLabel("TWS", value: nmeaManager.isTransmitting ? nmeaManager.tws.value : nil, precision: 1)
            ViewKit.displayLabel("HDG", value: nmeaManager.isTransmitting ? nmeaManager.heading.value : nil, precision: 0)
            Divider()
            ViewKit.displayLabel("Air °C", value: nmeaManager.isTransmitting && nmeaManager.sensorToggles.hasAirTempSensor ? nmeaManager.airTemp.value : nil, precision: 1)
            ViewKit.displayLabel("Humidity %", value: nmeaManager.isTransmitting && nmeaManager.sensorToggles.hasHumidtySensor ? nmeaManager.humidity.value : nil, precision: 0)
            ViewKit.displayLabel("Baro hPa", value: nmeaManager.isTransmitting && nmeaManager.sensorToggles.hasBarometer ? nmeaManager.barometer.value : nil, precision: 1)
        }
    }
}

#Preview {
    WindConfig(nmeaManager: PreviewData.nmeaManager)
        .frame(width: UIConstants.halfScreen / 1.2, height: UIConstants.minAppWindowHeight)
}

//MARK: - Subviews

private struct WindSentencesSection: View {
    @Binding var shouldSendMWV: Bool
    @Binding var shouldSendMWD: Bool
    @Binding var shouldSendVPW: Bool
    
    @Binding var showMWV: Bool
    @Binding var showMWD: Bool
    @Binding var showVPW: Bool
    
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {
        SettingsCard(title: "Wind Sentences") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                Picker("MWV Reference", selection: $nmeaManager.mwvReferenceMode) {
                    Text("Relative").tag(MWVReferenceMode.relative)
                    Text("True").tag(MWVReferenceMode.trueReference)
                    Text("Auto").tag(MWVReferenceMode.auto)
                }
                .pickerStyle(.segmented)

                Text("Use Relative for most receiver compatibility. Auto alternates between relative and true when both exist.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
                
                // MWV – Wind Speed & Angle
                ViewKit.SentenceRow(
                    "MWV - Wind Speed & Angle",
                    isOn: $shouldSendMWV,
                    interval: Binding(
                        get: { nmeaManager.sentenceInterval(for: .mwv) },
                        set: { nmeaManager.setInterval($0, for: .mwv) }
                    ),
                    intervalDisabled: !WindUIConditions.isMWVEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                    showInfo: $showMWV,
                    infoView: { AnyView(MWVHelpView().font(.caption)) }
                )
                .disabled(!WindUIConditions.isMWVEnabled(nmeaManager))
                
                if !WindUIConditions.isMWVEnabled(nmeaManager) {
                    SensorEnablePrompt(
                        message: UIStrings.Warnings.enableAnemometer,
                        actionTitle: "Enable Anemometer"
                    ) {
                        nmeaManager.sensorToggles.hasAnemometer = true
                    }
                }
                
                // MWD – Wind Direction & Speed
                ViewKit.SentenceRow(
                    "MWD - Wind Direction & Speed",
                    isOn: $shouldSendMWD,
                    interval: Binding(
                        get: { nmeaManager.sentenceInterval(for: .mwd) },
                        set: { nmeaManager.setInterval($0, for: .mwd) }
                    ),
                    intervalDisabled: !WindUIConditions.isMWDEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                    showInfo: $showMWD,
                    infoView: { AnyView(MWDHelpView().font(.caption)) }
                )
                .disabled(!WindUIConditions.isMWDEnabled(nmeaManager))

                if WindUIConditions.showMWDDependencyWarning(nmeaManager) {
                    windDependencyPrompt(sentence: "MWD")
                }

                // VPW – Speed Parallel to Wind
                ViewKit.SentenceRow(
                    "VPW - Speed Parallel to Wind",
                    isOn: $shouldSendVPW,
                    interval: Binding(
                        get: { nmeaManager.sentenceInterval(for: .vpw) },
                        set: { nmeaManager.setInterval($0, for: .vpw) }
                    ),
                    intervalDisabled: !WindUIConditions.isVPWEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                    showInfo: $showVPW,
                    infoView: { AnyView(VPWHelpView().font(.caption)) }
                )
                .disabled(!WindUIConditions.isVPWEnabled(nmeaManager))

                if WindUIConditions.showVPWDependencyWarning(nmeaManager) {
                    windDependencyPrompt(sentence: "VPW")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private func windDependencyPrompt(sentence: String) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
            Text("Compass or Gyro and Speed Log or GPS are required to activate \(sentence).")
                .foregroundStyle(DesignToken.Status.warning)
                .font(DesignToken.Typography.supporting)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DesignToken.Spacing.header) {
                if !nmeaManager.hasTrueHeading {
                    Button("Enable Magnetic Compass") {
                        nmeaManager.sensorToggles.hasCompass = true
                    }
                    .buttonStyle(.link)
                    .font(DesignToken.Typography.supporting)
                }
                if !nmeaManager.hasBoatSpeed {
                    Button("Enable Speed Log") {
                        nmeaManager.sensorToggles.hasSpeedLog = true
                    }
                    .buttonStyle(.link)
                    .font(DesignToken.Typography.supporting)
                }
            }
        }
    }
}

private struct AtmosphericSentencesSection: View {
    @Binding var shouldSendMDA: Bool
    @Binding var shouldSendXDR: Bool

    @Binding var showMDA: Bool
    @Binding var showXDR: Bool

    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        let hasSensor = nmeaManager.hasAtmosphericSensor

        SettingsCard(title: "Atmospheric Sentences") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                ViewKit.SentenceRow(
                    "MDA - Meteorological Composite",
                    isOn: $shouldSendMDA,
                    interval: Binding(
                        get: { nmeaManager.sentenceInterval(for: .mda) },
                        set: { nmeaManager.setInterval($0, for: .mda) }
                    ),
                    intervalDisabled: !hasSensor || !nmeaManager.isSentenceIntervalEditable,
                    showInfo: $showMDA,
                    infoView: { AnyView(MDAHelpView().font(.caption)) }
                )
                .disabled(!hasSensor)

                ViewKit.SentenceRow(
                    "XDR - Transducer Measurement",
                    isOn: $shouldSendXDR,
                    interval: Binding(
                        get: { nmeaManager.sentenceInterval(for: .xdr) },
                        set: { nmeaManager.setInterval($0, for: .xdr) }
                    ),
                    intervalDisabled: !hasSensor || !nmeaManager.isSentenceIntervalEditable,
                    showInfo: $showXDR,
                    infoView: { AnyView(XDRHelpView().font(.caption)) }
                )
                .disabled(!hasSensor)

                if !hasSensor {
                    SensorEnablePrompt(
                        message: UIStrings.Warnings.enableAtmosphericSensor,
                        actionTitle: "Enable Atmospheric Sensors"
                    ) {
                        nmeaManager.sensorToggles.hasAirTempSensor = true
                        nmeaManager.sensorToggles.hasHumidtySensor = true
                        nmeaManager.sensorToggles.hasBarometer = true
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
        }
    }
}

private struct WindUIConditions {
    
    static func isMWVEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasAnemometer
    }
    
    static func isMWDEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasAnemometer &&
        nmea.hasTrueHeading &&
        nmea.hasBoatSpeed
    }
    
    static func isVPWEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasAnemometer &&
        nmea.hasTrueHeading &&
        nmea.hasBoatSpeed
    }
    
    static func showAnemometerWarning(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasAnemometer
    }
    
    static func showMWDDependencyWarning(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasAnemometer &&
        (!nmea.hasTrueHeading || !nmea.hasBoatSpeed)
    }
    
    static func showVPWDependencyWarning(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasAnemometer &&
        (!nmea.hasTrueHeading || !nmea.hasBoatSpeed)
    }
}
