//
//  CompassView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

//
//  GPSConfig.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 01.07.25.
//

import SwiftUI
import MapKit

struct GPSConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @State private var showRMC: Bool = false
    @State private var showGGA: Bool = false
    @State private var showVTG: Bool = false
    @State private var showGLL: Bool = false
    @State private var showGSA: Bool = false
    @State private var showGSV: Bool = false
    @State private var showZDA: Bool = false
    @State private var showRMB: Bool = false
    @State private var showXTE: Bool = false

    
    var body: some View {
        SentencePage {
            GPSSentencesSection(
                nmeaManager: nmeaManager,
                shouldSendRMC: $nmeaManager.sentenceToggles.shouldSendRMC,
                shouldSendGGA: $nmeaManager.sentenceToggles.shouldSendGGA,
                shouldSendVTG: $nmeaManager.sentenceToggles.shouldSendVTG,
                shouldSendGLL: $nmeaManager.sentenceToggles.shouldSendGLL,
                shouldSendGSA: $nmeaManager.sentenceToggles.shouldSendGSA,
                shouldSendGSV: $nmeaManager.sentenceToggles.shouldSendGSV,
                shouldSendZDA: $nmeaManager.sentenceToggles.shouldSendZDA,
                shouldSendRMB: $nmeaManager.sentenceToggles.shouldSendRMB,
                shouldSendXTE: $nmeaManager.sentenceToggles.shouldSendXTE,
                showRMC: $showRMC,
                showGGA: $showGGA,
                showVTG: $showVTG,
                showGLL: $showGLL,
                showGSA: $showGSA,
                showGSV: $showGSV,
                showZDA: $showZDA,
                showRMB: $showRMB,
                showXTE: $showXTE
            )
        } preview: {
            GPSCoordinatePreview(nmeaManager: nmeaManager)
        }
    }
}

#Preview {
    GPSConfig(nmeaManager: PreviewData.nmeaManager)
        .frame(width: UIConstants.halfScreen / 2, height: UIConstants.minAppWindowHeight)
}

private struct GPSSentencesSection: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    @Binding var shouldSendRMC: Bool
    @Binding var shouldSendGGA: Bool
    @Binding var shouldSendVTG: Bool
    @Binding var shouldSendGLL: Bool
    @Binding var shouldSendGSA: Bool
    @Binding var shouldSendGSV: Bool
    @Binding var shouldSendZDA: Bool
    @Binding var shouldSendRMB: Bool
    @Binding var shouldSendXTE: Bool
    
    @Binding var showRMC: Bool
    @Binding var showGGA: Bool
    @Binding var showVTG: Bool
    @Binding var showGLL: Bool
    @Binding var showGSA: Bool
    @Binding var showGSV: Bool
    @Binding var showZDA: Bool
    @Binding var showRMB: Bool
    @Binding var showXTE: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            PersistentDisclosureGroup("Position", key: "gps.section.position") {
                sentenceRow("RMC - Recommended Minimum Navigation Info", isOn: $shouldSendRMC, sentence: .rmc, showInfo: $showRMC) {
                    AnyView(RMCHelpView().font(.caption))
                }
                sentenceRow("GGA - Fix Data", isOn: $shouldSendGGA, sentence: .gga, showInfo: $showGGA) {
                    AnyView(GGAHelpView().font(.caption))
                }
                sentenceRow("GLL - Geographic Position", isOn: $shouldSendGLL, sentence: .gll, showInfo: $showGLL) {
                    AnyView(GLLHelpView().font(.caption))
                }
            }

            PersistentDisclosureGroup("Velocity", key: "gps.section.velocity") {
                sentenceRow("VTG - Course and Speed Over Ground", isOn: $shouldSendVTG, sentence: .vtg, showInfo: $showVTG) {
                    AnyView(VTGHelpView().font(.caption))
                }
            }

            PersistentDisclosureGroup("GNSS", key: "gps.section.gnss") {
                sentenceRow("GSA - DOP and Active Satellites", isOn: $shouldSendGSA, sentence: .gsa, showInfo: $showGSA) {
                    AnyView(GSAHelpView().font(.caption))
                }
                sentenceRow("GSV - Satellites in View", isOn: $shouldSendGSV, sentence: .gsv, showInfo: $showGSV) {
                    AnyView(GSVHelpView().font(.caption))
                }
                sentenceRow("ZDA - Time and Date", isOn: $shouldSendZDA, sentence: .zda, showInfo: $showZDA) {
                    AnyView(ZDAHelpView().font(.caption))
                }
            }

            PersistentDisclosureGroup("Waypoint Navigation", key: "gps.section.waypoint") {
                waypointNavigationBlock
                sentenceRow(
                    "RMB - Recommended Minimum Navigation",
                    isOn: $shouldSendRMB,
                    sentence: .rmb,
                    intervalDisabled: !nmeaManager.waypointNavigation.isActive,
                    showInfo: $showRMB
                ) {
                    AnyView(RMBHelpView().font(.caption))
                }
                sentenceRow(
                    "XTE - Cross-Track Error",
                    isOn: $shouldSendXTE,
                    sentence: .xte,
                    intervalDisabled: !nmeaManager.waypointNavigation.isActive,
                    showInfo: $showXTE
                ) {
                    AnyView(XTEHelpView().font(.caption))
                }
            }

            if !GPSSentencesSection.isGPSEnabled(nmeaManager) {
                Text(UIStrings.Warnings.enableGPS)
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
                OpenSimulationSensorsButton()
            }
        }
        .disabled(!nmeaManager.sensorToggles.hasGPS)
        .toggleStyle(.switch)
        .controlSize(.regular)
    }

    @ViewBuilder
    private func sentenceRow(
        _ title: String,
        isOn: Binding<Bool>,
        sentence: NMEASentenceType,
        intervalDisabled: Bool = false,
        showInfo: Binding<Bool>,
        infoView: @escaping () -> AnyView
    ) -> some View {
        ViewKit.SentenceRow(
            title,
            isOn: isOn,
            interval: Binding(
                get: { nmeaManager.sentenceInterval(for: sentence) },
                set: { nmeaManager.setInterval($0, for: sentence) }
            ),
            intervalDisabled: intervalDisabled || !nmeaManager.isSentenceIntervalEditable,
            showInfo: showInfo,
            infoView: infoView
        )
    }

    @ViewBuilder private var waypointNavigationBlock: some View {
        Toggle("Active Waypoint", isOn: $nmeaManager.waypointNavigation.isActive)

        GroupBox("Origin Waypoint") {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                HStack {
                    Text("Name:")
                    TextField("", text: $nmeaManager.waypointNavigation.originName)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Lat:")
                    TextField("", value: $nmeaManager.waypointNavigation.originLatitude, formatter: FormatKit.decimalFormatter(fractionDigits: 6))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    Text("Lon:")
                    TextField("", value: $nmeaManager.waypointNavigation.originLongitude, formatter: FormatKit.decimalFormatter(fractionDigits: 6))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Set to Current Position") {
                    nmeaManager.waypointNavigation.originLatitude = nmeaManager.gpsData.latitude
                    nmeaManager.waypointNavigation.originLongitude = nmeaManager.gpsData.longitude
                    nmeaManager.persistLiveSettings()
                }
                .font(.caption)
            }
        }

        GroupBox("Destination Waypoint") {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                HStack {
                    Text("Name:")
                    TextField("", text: $nmeaManager.waypointNavigation.destinationName)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Lat:")
                    TextField("", value: $nmeaManager.waypointNavigation.destinationLatitude, formatter: FormatKit.decimalFormatter(fractionDigits: 6))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    Text("Lon:")
                    TextField("", value: $nmeaManager.waypointNavigation.destinationLongitude, formatter: FormatKit.decimalFormatter(fractionDigits: 6))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }

        HStack {
            Text("Arrival Radius:")
            TextField("", value: $nmeaManager.waypointNavigation.arrivalRadiusNm, formatter: FormatKit.decimalFormatter(fractionDigits: 2))
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
            Text("NM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()
    }

    static func isGPSEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasGPS
    }
}

private struct GPSCoordinatePreview: View {
    @Bindable var nmeaManager: NMEASimulator

    private var latitudeBinding: Binding<Double> {
        Binding(
            get: { nmeaManager.gpsData.latitude },
            set: { newValue in
                nmeaManager.gpsData.latitude = newValue
                nmeaManager.persistLiveSettings()
            }
        )
    }

    private var longitudeBinding: Binding<Double> {
        Binding(
            get: { nmeaManager.gpsData.longitude },
            set: { newValue in
                nmeaManager.gpsData.longitude = newValue
                nmeaManager.persistLiveSettings()
            }
        )
    }

    private var selectedCoordinateBinding: Binding<CLLocationCoordinate2D?> {
        Binding<CLLocationCoordinate2D?>(
            get: {
                CLLocationCoordinate2D(latitude: nmeaManager.gpsData.latitude,
                                       longitude: nmeaManager.gpsData.longitude)
            },
            set: { newValue in
                if let coord = newValue {
                    nmeaManager.gpsData.latitude = coord.latitude
                    nmeaManager.gpsData.longitude = coord.longitude
                    nmeaManager.persistLiveSettings()
                }
            }
        )
    }

    var body: some View {
        GroupBox(label: Label("Set Starting Coordinates", systemImage: "mappin.and.ellipse")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                HStack {
                    Text("Latitude:")
                    DeferredNumericField(
                        value: latitudeBinding,
                        fractionDigits: 6,
                        width: 100,
                        onEditingChange: { nmeaManager.isEditingGPSCoordinates = $0 }
                    )
                }
                HStack {
                    Text("Longitude:")
                    DeferredNumericField(
                        value: longitudeBinding,
                        fractionDigits: 6,
                        width: 100,
                        onEditingChange: { nmeaManager.isEditingGPSCoordinates = $0 }
                    )
                }
                Divider().padding(.vertical, 4)
                GPSMapSelectorView(selectedCoordinate: selectedCoordinateBinding)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if !nmeaManager.sensorToggles.hasGPS {
                    Text("Enable GPS in Simulation → Sensors to edit position and map starting coordinates.")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                    OpenSimulationSensorsButton()
                }
            }
            .disabled(!nmeaManager.sensorToggles.hasGPS)
        }
    }
}
