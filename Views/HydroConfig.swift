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
        GeometryReader { _ in
            HStack(alignment: .top, spacing: UIConstants.spacing * 2) {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
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
                }
                .padding()
            }
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
        GroupBox(label: Text("Depth")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                
                // DBT – Depth Below Transducer
                ViewKit.ToggleRowWithInfo(
                    "DBT - Depth Below Transducer",
                    isOn: $shouldSendDBT,
                    showInfo: $showDBT,
                    infoView: { AnyView(DBTHelpView().font(.caption)) }
                )
                .disabled(!HydroUIConditions.isDBTEnabled(nmeaManager))
                
                
                // DPT – Depth of Water (requires offset)
                ViewKit.ToggleRowWithInfo(
                    "DPT - Depth of Water",
                    isOn: $shouldSendDPT,
                    showInfo: $showDPT,
                    infoView: { AnyView(DPTHelpView().font(.caption)) }
                )
                .disabled(!HydroUIConditions.isDPTEnabled(nmeaManager))
                
                if HydroUIConditions.showEchoSounderWarning(nmeaManager) {
                    Text(UIStrings.Warnings.enableEchoSounder)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
                if HydroUIConditions.showOffsetInput(nmeaManager) {
                    // show offset input and help
                    // Offset input with help
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("Offset (m):")
                                .font(.caption)
                            
                            Button(action: {
                                withAnimation {
                                    showOffsetHelp.toggle()
                                }
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 110, alignment: .leading)
                        
                        TextField("0.00", value: $nmeaManager.depthOffsetMeters, formatter: FormatKit.decimalFormatter(fractionDigits: 2))
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    .padding(.leading, 4)
                    if showOffsetHelp {
                        Text("Enter the distance between your transducer and the waterline (positive) or the keel (negative).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                            .transition(.opacity)
                    }
                }
                if HydroUIConditions.showInvalidOffsetWarning(nmeaManager) {
                    Text("Please enter a valid non-zero depth offset (e.g., 0.30 or -0.70) to activate DPT.")
                        .foregroundStyle(AppColors.warning)
                        .font(.caption2)
                        .padding(.leading, 4)
                }
            }
            .toggleStyle(.switch)
        }
        GroupBox(label: Text("Sea Water Temperature")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                
                ViewKit.ToggleRowWithInfo(
                    "MTW - Water Temperature",
                    isOn: $shouldSendMTW,
                    showInfo: $showMTW,
                    infoView: { AnyView(MTWHelpView().font(.caption)) }
                )
                .disabled(!HydroUIConditions.isMTWEnabled(nmeaManager))
                .toggleStyle(.switch)
                
                if HydroUIConditions.showMTWWarning(nmeaManager) {
                    Text(UIStrings.Warnings.enableWaterTempSensor)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
            }
        }
        GroupBox(label: Text("Speed")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                // MARK: - VHW – Water Speed and Heading
                ViewKit.ToggleRowWithInfo(
                    "VHW - Water Speed and Heading",
                    isOn: $shouldSendVHW,
                    showInfo: $showVHW,
                    infoView: { AnyView(VHWHelpView().font(.caption)) }
                )
                .disabled(!HydroUIConditions.isVHWEnabled(nmeaManager))
                
                if HydroUIConditions.showVHWMissingBothNote(nmeaManager) {
                    Text("Activate Speed Log or Magnetic Compass to enable the sentence.")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                } else {
                    if HydroUIConditions.showVHWSpeedLogNote(nmeaManager) {
                        Text(UIStrings.InfoMessage.speedLogInfoNote)
                            .font(.caption2)
                            .foregroundStyle(AppColors.info)
                            .padding(.leading, 4)
                    }
                    if HydroUIConditions.showVHWCompassNote(nmeaManager) {
                        Text(UIStrings.InfoMessage.compassInfoNote)
                            .font(.caption2)
                            .foregroundStyle(AppColors.info)
                            .padding(.leading, 4)
                    }
                }
                
                // MARK: - VBW – Dual Ground/Water Speed
                ViewKit.ToggleRowWithInfo(
                    "VBW - Dual Ground/Water Speed",
                    isOn: $shouldSendVBW,
                    showInfo: $showVBW,
                    infoView: { AnyView(VBWHelpView().font(.caption)) }
                )
                .disabled(!HydroUIConditions.isVBWEnabled(nmeaManager))
                
                if HydroUIConditions.showVBWMissingBothNote(nmeaManager) {
                    Text("Activate Speed Log or GPS to enable the sentence.")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                } else {
                    if HydroUIConditions.showVBWSpeedLogNote(nmeaManager) {
                        Text(UIStrings.InfoMessage.speedLogInfoNote)
                            .font(.caption2)
                            .foregroundStyle(AppColors.info)
                            .padding(.leading, 4)
                    }
                    if HydroUIConditions.showVBWGPSNote(nmeaManager) {
                        Text(UIStrings.InfoMessage.sogInfoNote)
                            .font(.caption2)
                            .foregroundStyle(AppColors.info)
                            .padding(.leading, 4)
                    }
                }
                
                // MARK: - VLW – Distance Traveled Through Water
                ViewKit.ToggleRowWithInfo(
                    "VLW - Distance Traveled Through Water",
                    isOn: $shouldSendVLW,
                    showInfo: $showVLW,
                    infoView: { AnyView(VLWHelpView().font(.caption)) }
                )
                .disabled(!HydroUIConditions.isVLWEnabled(nmeaManager))
                
                if HydroUIConditions.showVLWSpeedLogNote(nmeaManager) {
                    Text(UIStrings.Warnings.enableSpeedLog)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
            }
            .toggleStyle(.switch)
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
        let offset = nmea.depthOffsetMeters
        return offset != 0 && abs(offset) <= 99
    }
    
    static func showEchoSounderWarning(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasEchoSounder
    }
    
    static func showOffsetInput(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasEchoSounder
    }
    
    static func showInvalidOffsetWarning(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasEchoSounder && !isDPTEnabled(nmea)
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
        nmea.sensorToggles.hasSpeedLog || nmea.sensorToggles.hasCompass
    }
    
    static func showVHWCompassNote(_ nmea: NMEASimulator) -> Bool {
        nmea.sentenceToggles.shouldSendVHW && !nmea.sensorToggles.hasCompass
    }
    
    static func showVHWSpeedLogNote(_ nmea: NMEASimulator) -> Bool {
        nmea.sentenceToggles.shouldSendVHW && !nmea.sensorToggles.hasSpeedLog
    }
    
    static func showVHWMissingBothNote(_ nmea: NMEASimulator) -> Bool {
        !nmea.sensorToggles.hasSpeedLog && !nmea.sensorToggles.hasCompass
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
