//
//  HeadingConfig.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 25.06.25.
//

import SwiftUI

struct HeadingConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @State var showHDG: Bool = false
    @State var showHDT: Bool = false
    @State var showROT: Bool = false
    
    var body: some View {
        SentencePage {
            HeadingSentencesSection(
                shouldSendHDG: $nmeaManager.sentenceToggles.shouldSendHDG,
                shouldSendHDT: $nmeaManager.sentenceToggles.shouldSendHDT,
                shouldSendROT: $nmeaManager.sentenceToggles.shouldSendROT,
                showHDG: $showHDG,
                showHDT: $showHDT,
                showROT: $showROT,
                nmeaManager: nmeaManager
            )
        } live: {
            ViewKit.displayLabel("Magnetic", value: nmeaManager.isTransmitting ? nmeaManager.heading.value : nil, precision: 1)
            ViewKit.displayLabel("True (Gyro)", value: nmeaManager.isTransmitting ? nmeaManager.gyroHeading.value : nil, precision: 1)
        }
    }
}

#Preview {
    HeadingConfig(nmeaManager: PreviewData.nmeaManager)
        .frame(width: UIConstants.halfScreen / 1.2, height: UIConstants.minAppWindowHeight)
}

// MARK: - Subviews

private struct HeadingSentencesSection: View {
    @Binding var shouldSendHDG: Bool
    @Binding var shouldSendHDT: Bool
    @Binding var shouldSendROT: Bool
    
    @Binding var showHDG: Bool
    @Binding var showHDT: Bool
    @Binding var showROT: Bool
    
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            SettingsCard(title: "Magnetic Compass") {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                    // HDG – Magnetic Heading
                    ViewKit.SentenceRow(
                        "HDG - Heading, Deviation, Variation",
                        isOn: $shouldSendHDG,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .hdg) },
                            set: { nmeaManager.setInterval($0, for: .hdg) }
                        ),
                        intervalDisabled: !HeadingUIConditions.isHDGEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showHDG,
                        infoView: { AnyView(HDGHelpView().font(.caption)) }
                    )
                    .disabled(!HeadingUIConditions.isHDGEnabled(nmeaManager))

                    if HeadingUIConditions.showHDGWarning(nmeaManager) {
                        SensorEnablePrompt(
                            message: UIStrings.Warnings.enableMagneticCompass,
                            actionTitle: "Enable Magnetic Compass"
                        ) {
                            nmeaManager.sensorToggles.hasCompass = true
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            SettingsCard(title: "Gyro Compass") {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                    // HDT – True Heading
                    ViewKit.SentenceRow(
                        "HDT - Heading, True",
                        isOn: $shouldSendHDT,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .hdt) },
                            set: { nmeaManager.setInterval($0, for: .hdt) }
                        ),
                        intervalDisabled: !HeadingUIConditions.isHDTEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showHDT,
                        infoView: { AnyView(HDTHelpView().font(.caption)) }
                    )
                    .disabled(!HeadingUIConditions.isHDTEnabled(nmeaManager))

                    // ROT – Rate of Turn
                    ViewKit.SentenceRow(
                        "ROT - Rate of Turn",
                        isOn: $shouldSendROT,
                        interval: Binding(
                            get: { nmeaManager.sentenceInterval(for: .rot) },
                            set: { nmeaManager.setInterval($0, for: .rot) }
                        ),
                        intervalDisabled: !HeadingUIConditions.isROTEnabled(nmeaManager) || !nmeaManager.isSentenceIntervalEditable,
                        showInfo: $showROT,
                        infoView: { AnyView(ROTHelpView().font(.caption)) }
                    )
                    .disabled(!HeadingUIConditions.isROTEnabled(nmeaManager))

                    if HeadingUIConditions.showGyroWarning(nmeaManager) {
                        SensorEnablePrompt(
                            message: UIStrings.Warnings.enableGyroCompass,
                            actionTitle: "Enable Gyro Compass"
                        ) {
                            nmeaManager.sensorToggles.hasGyro = true
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
            }
        }
    }
}
private struct HeadingUIConditions {
    
    static func isHDGEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasCompass
    }
    
    static func isHDTEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasGyro
    }
    
    static func isROTEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasGyro
    }
    
    static func showHDGWarning(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasCompass
    }
    
    static func showGyroWarning(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasGyro
    }
}
