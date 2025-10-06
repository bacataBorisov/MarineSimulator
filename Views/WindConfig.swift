// WindView.swift
// Extending with live-calculated AWA, AWS, AWD, TWA

import SwiftUI

struct WindConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @State var showMWV: Bool = false
    @State var showMWD: Bool = false
    @State var showVPW: Bool = false
    
    var body: some View {
        GeometryReader { _ in
            HStack (alignment: .top, spacing: UIConstants.spacing * 2) {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    WindSentencesSection(
                        shouldSendMWV: $nmeaManager.sentenceToggles.shouldSendMWV,
                        shouldSendMWD: $nmeaManager.sentenceToggles.shouldSendMWD,
                        shouldSendVPW: $nmeaManager.sentenceToggles.shouldSendVPW,
                        showMWV: $showMWV,
                        showMWD: $showMWD,
                        showVPW: $showVPW,
                        nmeaManager: nmeaManager
                    )
                }
                .padding()
            }
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
        GroupBox(label: Label("Wind Sentences", systemImage: "list.bullet.rectangle")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                
                // MWV – Wind Speed & Angle
                ViewKit.ToggleRowWithInfo(
                    "MWV - Wind Speed & Angle",
                    isOn: $shouldSendMWV,
                    showInfo: $showMWV,
                    infoView: { AnyView(MWVHelpView().font(.caption)) }
                )
                .disabled(!WindUIConditions.isMWVEnabled(nmeaManager))
                
                if !WindUIConditions.isMWVEnabled(nmeaManager) {
                    Text(UIStrings.Warnings.enableAnemometer)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
                
                // MWD – Wind Direction & Speed
                ViewKit.ToggleRowWithInfo(
                    "MWD - Wind Direction & Speed",
                    isOn: $shouldSendMWD,
                    showInfo: $showMWD,
                    infoView: { AnyView(MWDHelpView().font(.caption)) }
                )
                .disabled(!WindUIConditions.isMWDEnabled(nmeaManager))

                if WindUIConditions.showMWDDependencyWarning(nmeaManager) {
                    Text("Enable Compass / Gyro and Boat Speed to activate MWD.")
                        .foregroundStyle(AppColors.warning)
                        .font(.caption2)
                        .padding(.leading, 4)
                }

                // VPW – Speed Parallel to Wind
                ViewKit.ToggleRowWithInfo(
                    "VPW - Speed Parallel to Wind",
                    isOn: $shouldSendVPW,
                    showInfo: $showVPW,
                    infoView: { AnyView(VPWHelpView().font(.caption)) }
                )
                .disabled(!WindUIConditions.isVPWEnabled(nmeaManager))

                if WindUIConditions.showVPWDependencyWarning(nmeaManager) {
                    Text("Enable Compass / Gyro and Boat Speed to activate VPW.")
                        .foregroundStyle(AppColors.warning)
                        .font(.caption2)
                        .padding(.leading, 4)
                }
            }
            .toggleStyle(.switch)
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
