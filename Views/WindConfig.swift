// WindView.swift
// Extending with live-calculated AWA, AWS, AWD, TWA

import SwiftUI

struct WindConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @State var showMWV: Bool = false
    @State var showMWD: Bool = false
    @State var showVPW: Bool = false
    
    var body: some View {
        SentencePanelLayout {
            WindSentencesSection(
                shouldSendMWV: $nmeaManager.sentenceToggles.shouldSendMWV,
                shouldSendMWD: $nmeaManager.sentenceToggles.shouldSendMWD,
                shouldSendVPW: $nmeaManager.sentenceToggles.shouldSendVPW,
                showMWV: $showMWV,
                showMWD: $showMWD,
                showVPW: $showVPW,
                nmeaManager: nmeaManager
            )
        } preview: {
            VStack(spacing: UIConstants.spacing * 2) {
                ViewKit.displayLabel("TWD", value: nmeaManager.twd.value, precision: 0)
                ViewKit.displayLabel("TWS", value: nmeaManager.tws.value, precision: 1)
                ViewKit.displayLabel("HDG", value: nmeaManager.heading.value, precision: 0)
            }
            .padding()
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
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
                Picker("MWV Reference", selection: $nmeaManager.mwvReferenceMode) {
                    Text("Relative").tag(MWVReferenceMode.relative)
                    Text("True").tag(MWVReferenceMode.trueReference)
                    Text("Auto").tag(MWVReferenceMode.auto)
                }
                .pickerStyle(.segmented)

                Text("Use Relative for most receiver compatibility. Auto alternates between relative and true when both exist.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
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
                    Text(UIStrings.Warnings.enableAnemometer)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                    OpenSimulationSensorsButton()
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
                    Text("Enable Compass / Gyro and Speed Log or GPS to activate MWD.")
                        .foregroundStyle(AppColors.warning)
                        .font(.caption2)
                        .padding(.leading, 4)
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
                    Text("Enable Compass / Gyro and Speed Log or GPS to activate VPW.")
                        .foregroundStyle(AppColors.warning)
                        .font(.caption2)
                        .padding(.leading, 4)
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
