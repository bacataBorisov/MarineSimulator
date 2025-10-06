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
        GeometryReader { _ in
            HStack(alignment: .top, spacing: UIConstants.spacing * 2) {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    HeadingSentencesSection(
                        shouldSendHDG: $nmeaManager.sentenceToggles.shouldSendHDG,
                        shouldSendHDT: $nmeaManager.sentenceToggles.shouldSendHDT,
                        shouldSendROT: $nmeaManager.sentenceToggles.shouldSendROT,
                        showHDG: $showHDG,
                        showHDT: $showHDT,
                        showROT: $showROT,
                        nmeaManager: nmeaManager
                    )
                }
                .padding()
            }
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
        GroupBox(label: Text("Magnetic Compass")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                
                // HDG – Magnetic Heading
                ViewKit.ToggleRowWithInfo(
                    "HDG - Heading, Deviation, Variation",
                    isOn: $shouldSendHDG,
                    showInfo: $showHDG,
                    infoView: { AnyView(HDGHelpView().font(.caption)) }
                )
                .disabled(!HeadingUIConditions.isHDGEnabled(nmeaManager))
                
                if HeadingUIConditions.showHDGWarning(nmeaManager) {
                    Text(UIStrings.Warnings.enableMagneticCompass)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
            }
            .toggleStyle(.switch)
        }
        GroupBox(label: Text("Gyro Compass")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                // HDT – True Heading
                ViewKit.ToggleRowWithInfo(
                    "HDT - Heading, True",
                    isOn: $shouldSendHDT,
                    showInfo: $showHDT,
                    infoView: { AnyView(HDTHelpView().font(.caption)) }
                )
                .disabled(!HeadingUIConditions.isHDTEnabled(nmeaManager))
                
                // ROT – Rate of Turn
                ViewKit.ToggleRowWithInfo(
                    "ROT - Rate of Turn",
                    isOn: $shouldSendROT,
                    showInfo: $showROT,
                    infoView: { AnyView(ROTHelpView().font(.caption)) }
                )
                .disabled(!HeadingUIConditions.isROTEnabled(nmeaManager))
                
                if HeadingUIConditions.showGyroWarning(nmeaManager) {
                    Text(UIStrings.Warnings.enableGyroCompass)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
            }
            .toggleStyle(.switch)
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
