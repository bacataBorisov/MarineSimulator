//
//  HydroConfig.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 28.06.25.
//

import SwiftUI

struct HydroConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @State var showDBT: Bool = false
    @State var showDPT: Bool = false
    @State var showMTW: Bool = false
    @State var showVHW: Bool = false
    @State var showVBW: Bool = false
    @State var showVLW: Bool = false
    
    var body: some View {
        SentencePage {
            HydroSentencesSection(
                nmeaManager: nmeaManager, shouldSendDBT: $nmeaManager.sentenceToggles.shouldSendDBT,
                shouldSendDPT: $nmeaManager.sentenceToggles.shouldSendDPT,
                shouldSendMTW: $nmeaManager.sentenceToggles.shouldSendMTW,
                shouldSendVHW: $nmeaManager.sentenceToggles.shouldSendVHW,
                shouldSendVBW: $nmeaManager.sentenceToggles.shouldSendVBW,
                shouldSendVLW: $nmeaManager.sentenceToggles.shouldSendVLW,
                showDBT: $showDBT,
                showDPT: $showDPT,
                showMTW: $showMTW,
                showVHW: $showVHW,
                showVBW: $showVBW,
                showVLW: $showVLW
            )
        } live: {
            ViewKit.displayLabel("Depth", value: nmeaManager.isTransmitting ? nmeaManager.depth.value : nil, precision: 1)
            ViewKit.displayLabel("STW", value: nmeaManager.isTransmitting ? nmeaManager.speed.value : nil, precision: 1)
            ViewKit.displayLabel("Sea °C", value: nmeaManager.isTransmitting ? nmeaManager.seaTemp.value : nil, precision: 1)
        }
    }
}

#Preview {
    HydroConfig(nmeaManager: PreviewData.nmeaManager)
        .frame(width: UIConstants.halfScreen / 2, height: UIConstants.minAppWindowHeight)
}

//MARK: - Subviews

private struct HydroSentencesSection: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @Binding var shouldSendDBT: Bool
    @Binding var shouldSendDPT: Bool
    @Binding var shouldSendMTW: Bool
    @Binding var shouldSendVHW: Bool
    @Binding var shouldSendVBW: Bool
    @Binding var shouldSendVLW: Bool
    
    @Binding var showDBT: Bool
    @Binding var showDPT: Bool
    @Binding var showMTW: Bool
    @Binding var showVHW: Bool
    @Binding var showVBW: Bool
    @Binding var showVLW: Bool
    
    @State private var showOffsetHelp: Bool = false
    
    private var isOffsetValid: Bool {
        let value = nmeaManager.depthOffsetMeters
        return value != 0 && abs(value) <= 99
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            SettingsCard(title: "Depth") {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                    // DBT – Depth Below Transducer
                    ViewKit.SentenceRow(
                        "DBT - Depth Below Transducer",
                        isOn: $shouldSendDBT,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .dbt) },
                            set: { nmeaManager.setInterval($0, for: .dbt) }
                        ),
                        intervalDisabled: !HydroUIConditions.isDBTEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showDBT,
                        infoView: { AnyView(DBTHelpView().font(.caption)) }
                    )
                    .disabled(!HydroUIConditions.isDBTEnabled(nmeaManager))

                    // DPT – Depth of Water
                    ViewKit.SentenceRow(
                        "DPT - Depth of Water",
                        isOn: $shouldSendDPT,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .dpt) },
                            set: { nmeaManager.setInterval($0, for: .dpt) }
                        ),
                        intervalDisabled: !HydroUIConditions.isDPTEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showDPT,
                        infoView: { AnyView(DPTHelpView().font(.caption)) }
                    )
                    .disabled(!HydroUIConditions.isDPTEnabled(nmeaManager))

                    if HydroUIConditions.showEchoSounderWarning(nmeaManager) {
                        SensorEnablePrompt(
                            message: UIStrings.Warnings.enableEchoSounder,
                            actionTitle: "Enable Echo Sounder"
                        ) {
                            nmeaManager.sensorToggles.hasEchoSounder = true
                        }
                    }
                    if HydroUIConditions.showOffsetInput(nmeaManager) {
                        HStack(spacing: DesignToken.Spacing.header) {
                            HStack(spacing: DesignToken.Spacing.stacked) {
                                Text("Offset (m):")
                                    .font(DesignToken.Typography.supporting)
                                    .foregroundStyle(DesignToken.Status.neutral)

                                Button {
                                    withAnimation {
                                        showOffsetHelp.toggle()
                                    }
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(DesignToken.accentPrimary)
                                }
                                .buttonStyle(.plain)
                                .help("Explain depth offset")
                                .accessibilityLabel("Depth offset help")
                            }
                            .frame(width: 110, alignment: .leading)

                            DeferredNumericField(
                                value: $nmeaManager.depthOffsetMeters,
                                fractionDigits: 2,
                                width: 70
                            )
                            .font(DesignToken.Typography.supporting)
                            .accessibilityLabel("Depth offset in meters")
                        }
                        if showOffsetHelp {
                            Text("Enter the distance between your transducer and the waterline (positive) or the keel (negative).")
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.neutral)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    if HydroUIConditions.showInvalidOffsetWarning(nmeaManager) {
                        Text("Please enter a valid depth offset between -99 m and 99 m.")
                            .foregroundStyle(DesignToken.Status.warning)
                            .font(DesignToken.Typography.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            SettingsCard(title: "Sea Water Temperature") {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                    ViewKit.SentenceRow(
                        "MTW - Water Temperature",
                        isOn: $shouldSendMTW,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .mtw) },
                            set: { nmeaManager.setInterval($0, for: .mtw) }
                        ),
                        intervalDisabled: !HydroUIConditions.isMTWEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showMTW,
                        infoView: { AnyView(MTWHelpView().font(.caption)) }
                    )
                    .disabled(!HydroUIConditions.isMTWEnabled(nmeaManager))

                    if HydroUIConditions.showMTWWarning(nmeaManager) {
                        SensorEnablePrompt(
                            message: UIStrings.Warnings.enableWaterTempSensor,
                            actionTitle: "Enable Water Temperature"
                        ) {
                            nmeaManager.sensorToggles.hasWaterTempSensor = true
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            SettingsCard(title: "Speed") {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                    // MARK: - VHW – Water Speed and Heading
                    ViewKit.SentenceRow(
                        "VHW - Water Speed and Heading",
                        isOn: $shouldSendVHW,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .vhw) },
                            set: { nmeaManager.setInterval($0, for: .vhw) }
                        ),
                        intervalDisabled: !HydroUIConditions.isVHWEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showVHW,
                        infoView: { AnyView(VHWHelpView().font(.caption)) }
                    )
                    .disabled(!HydroUIConditions.isVHWEnabled(nmeaManager))

                    if HydroUIConditions.showVHWMissingBothNote(nmeaManager) {
                        SensorEnablePrompt(
                            message: "Speed Log, Magnetic Compass, or Gyro Compass is required to enable VHW.",
                            actionTitle: "Enable Speed Log"
                        ) {
                            nmeaManager.sensorToggles.hasSpeedLog = true
                        }
                    } else {
                        if HydroUIConditions.showVHWSpeedLogNote(nmeaManager) {
                            Text(UIStrings.InfoMessage.speedLogInfoNote)
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.info)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if HydroUIConditions.showVHWCompassNote(nmeaManager) {
                            Text(UIStrings.InfoMessage.compassInfoNote)
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.info)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // MARK: - VBW – Dual Ground/Water Speed
                    ViewKit.SentenceRow(
                        "VBW - Dual Ground/Water Speed",
                        isOn: $shouldSendVBW,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .vbw) },
                            set: { nmeaManager.setInterval($0, for: .vbw) }
                        ),
                        intervalDisabled: !HydroUIConditions.isVBWEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showVBW,
                        infoView: { AnyView(VBWHelpView().font(.caption)) }
                    )
                    .disabled(!HydroUIConditions.isVBWEnabled(nmeaManager))

                    if HydroUIConditions.showVBWMissingBothNote(nmeaManager) {
                        SensorEnablePrompt(
                            message: "Speed Log or GPS is required to enable VBW.",
                            actionTitle: "Enable Speed Log"
                        ) {
                            nmeaManager.sensorToggles.hasSpeedLog = true
                        }
                    } else {
                        if HydroUIConditions.showVBWSpeedLogNote(nmeaManager) {
                            Text(UIStrings.InfoMessage.speedLogInfoNote)
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.info)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if HydroUIConditions.showVBWGPSNote(nmeaManager) {
                            Text(UIStrings.InfoMessage.sogInfoNote)
                                .font(DesignToken.Typography.supporting)
                                .foregroundStyle(DesignToken.Status.info)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // MARK: - VLW – Distance Traveled Through Water
                    ViewKit.SentenceRow(
                        "VLW - Distance Traveled Through Water",
                        isOn: $shouldSendVLW,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .vlw) },
                            set: { nmeaManager.setInterval($0, for: .vlw) }
                        ),
                        intervalDisabled: !HydroUIConditions.isVLWEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showVLW,
                        infoView: { AnyView(VLWHelpView().font(.caption)) }
                    )
                    .disabled(!HydroUIConditions.isVLWEnabled(nmeaManager))

                    if HydroUIConditions.showVLWSpeedLogNote(nmeaManager) {
                        SensorEnablePrompt(
                            message: UIStrings.Warnings.enableSpeedLog,
                            actionTitle: "Enable Speed Log"
                        ) {
                            nmeaManager.sensorToggles.hasSpeedLog = true
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }
        }
    }
}

// MARK: - HydroUIConditions

private struct HydroUIConditions {
    
    // MARK: - Depth
    
    static func isDBTEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasEchoSounder
    }
    
    static func isDPTEnabled(_ nmea: NMEASimulator) -> Bool {
        guard nmea.sensorToggles.hasEchoSounder else { return false }
        return abs(nmea.depthOffsetMeters) <= 99
    }
    
    static func showEchoSounderWarning(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasEchoSounder
    }
    
    static func showOffsetInput(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasEchoSounder
    }
    
    static func showInvalidOffsetWarning(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasEchoSounder && abs(nmea.depthOffsetMeters) > 99
    }
    
    // MARK: - Sea Water Temperature
    
    static func isMTWEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasWaterTempSensor
    }
    static func showMTWWarning(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasWaterTempSensor
    }
    
    // MARK: - Speed Sentences (Minimal Version)
    
    static func isVHWEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasSpeedLog || nmea.sensorToggles.hasCompass || nmea.sensorToggles.hasGyro
    }
    
    static func showVHWCompassNote(_ nmea: NMEASimulator) -> Bool {
        nmea.sentenceToggles.shouldSendVHW && !nmea.sensorToggles.hasCompass
    }
    
    static func showVHWSpeedLogNote(_ nmea: NMEASimulator) -> Bool {
        nmea.sentenceToggles.shouldSendVHW && !nmea.sensorToggles.hasSpeedLog
    }
    
    static func showVHWMissingBothNote(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasSpeedLog && !nmea.sensorToggles.hasCompass && !nmea.sensorToggles.hasGyro
    }
    
    static func isVBWEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasSpeedLog || nmea.sensorToggles.hasGPS
    }
    
    static func showVBWGPSNote(_ nmea: NMEASimulator) -> Bool {
        nmea.sentenceToggles.shouldSendVBW && !nmea.sensorToggles.hasGPS
    }
    
    static func showVBWSpeedLogNote(_ nmea: NMEASimulator) -> Bool {
        nmea.sentenceToggles.shouldSendVBW && !nmea.sensorToggles.hasSpeedLog
    }
    
    static func showVBWMissingBothNote(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasGPS && !nmea.sensorToggles.hasSpeedLog
    }
    
    static func isVLWEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasSpeedLog
    }
    
    static func showVLWSpeedLogNote(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasSpeedLog
    }
}
