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
        SettingsCard(title: "GPS Sentences") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                Group {
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

                    Divider()

                    PersistentDisclosureGroup("Velocity", key: "gps.section.velocity") {
                        sentenceRow("VTG - Course and Speed Over Ground", isOn: $shouldSendVTG, sentence: .vtg, showInfo: $showVTG) {
                            AnyView(VTGHelpView().font(.caption))
                        }
                    }

                    Divider()

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

                    Divider()

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
                }
                .disabled(!nmeaManager.sensorToggles.hasGPS)

                if !GPSSentencesSection.isGPSEnabled(nmeaManager) {
                    SensorEnablePrompt(
                        message: UIStrings.Warnings.enableGPS,
                        actionTitle: "Enable GPS"
                    ) {
                        nmeaManager.sensorToggles.hasGPS = true
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
        }
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

        VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
            Text("Origin Waypoint")
                .font(DesignToken.Typography.supporting.weight(.semibold))
                .foregroundStyle(DesignToken.Status.neutral)

            HStack(spacing: DesignToken.Spacing.row) {
                Text("Name:")
                    .font(DesignToken.Typography.field)
                TextField("Origin", text: $nmeaManager.waypointNavigation.originName)
                    .frame(width: 68)
                    .textFieldStyle(.roundedBorder)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignToken.Spacing.row) {
                    waypointLatLonFields(
                        lat: $nmeaManager.waypointNavigation.originLatitude,
                        lon: $nmeaManager.waypointNavigation.originLongitude,
                        labelPrefix: "Origin"
                    )
                }
                VStack(alignment: .leading, spacing: DesignToken.Spacing.related) {
                    waypointLatLonFields(
                        lat: $nmeaManager.waypointNavigation.originLatitude,
                        lon: $nmeaManager.waypointNavigation.originLongitude,
                        labelPrefix: "Origin"
                    )
                }
            }
            Button("Set to Current Position") {
                nmeaManager.waypointNavigation.originLatitude = nmeaManager.gpsData.latitude
                nmeaManager.waypointNavigation.originLongitude = nmeaManager.gpsData.longitude
                nmeaManager.persistLiveSettings()
            }
            .font(DesignToken.Typography.supporting)
        }
        .padding(DesignToken.Spacing.header)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignToken.Surface.nested,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.compactCard, style: .continuous)
        )

        VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
            Text("Destination Waypoint")
                .font(DesignToken.Typography.supporting.weight(.semibold))
                .foregroundStyle(DesignToken.Status.neutral)

            HStack(spacing: DesignToken.Spacing.row) {
                Text("Name:")
                    .font(DesignToken.Typography.field)
                TextField("Destination", text: $nmeaManager.waypointNavigation.destinationName)
                    .frame(width: 68)
                    .textFieldStyle(.roundedBorder)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignToken.Spacing.row) {
                    waypointLatLonFields(
                        lat: $nmeaManager.waypointNavigation.destinationLatitude,
                        lon: $nmeaManager.waypointNavigation.destinationLongitude,
                        labelPrefix: "Destination"
                    )
                }
                VStack(alignment: .leading, spacing: DesignToken.Spacing.related) {
                    waypointLatLonFields(
                        lat: $nmeaManager.waypointNavigation.destinationLatitude,
                        lon: $nmeaManager.waypointNavigation.destinationLongitude,
                        labelPrefix: "Destination"
                    )
                }
            }
        }
        .padding(DesignToken.Spacing.header)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignToken.Surface.nested,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.compactCard, style: .continuous)
        )

        HStack(spacing: DesignToken.Spacing.row) {
            Text("Arrival Radius:")
                .font(DesignToken.Typography.field)
            DeferredNumericField(
                value: $nmeaManager.waypointNavigation.arrivalRadiusNm,
                fractionDigits: 2,
                width: 64
            )
            .accessibilityLabel("Arrival radius in nautical miles")
            Text("NM")
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)
        }

        Divider()
    }

    @ViewBuilder
    private func waypointLatLonFields(
        lat: Binding<Double>,
        lon: Binding<Double>,
        labelPrefix: String
    ) -> some View {
        HStack(spacing: DesignToken.Spacing.related) {
            Text("Lat:")
                .font(DesignToken.Typography.field)
            DeferredNumericField(
                value: lat,
                fractionDigits: 6,
                width: 100
            )
            .accessibilityLabel("\(labelPrefix) latitude")
        }
        HStack(spacing: DesignToken.Spacing.related) {
            Text("Lon:")
                .font(DesignToken.Typography.field)
            DeferredNumericField(
                value: lon,
                fractionDigits: 6,
                width: 100
            )
            .accessibilityLabel("\(labelPrefix) longitude")
        }
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
                nmeaManager.applyUserGPSCoordinates(latitude: newValue, longitude: nmeaManager.gpsData.longitude)
                nmeaManager.persistLiveSettings()
            }
        )
    }

    private var longitudeBinding: Binding<Double> {
        Binding(
            get: { nmeaManager.gpsData.longitude },
            set: { newValue in
                nmeaManager.applyUserGPSCoordinates(latitude: nmeaManager.gpsData.latitude, longitude: newValue)
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
                    nmeaManager.applyUserGPSCoordinates(latitude: coord.latitude, longitude: coord.longitude)
                    nmeaManager.persistLiveSettings()
                }
            }
        )
    }

    var body: some View {
        SettingsCard(title: "Set Starting Coordinates") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                Group {
                    Grid(alignment: .leading, horizontalSpacing: DesignToken.Spacing.field, verticalSpacing: DesignToken.Spacing.row) {
                        GridRow {
                            Text("Latitude")
                                .font(DesignToken.Typography.field)
                                .foregroundStyle(DesignToken.Status.neutral)
                            DeferredNumericField(
                                value: latitudeBinding,
                                fractionDigits: 6,
                                width: 120,
                                onEditingChange: { nmeaManager.isEditingGPSCoordinates = $0 }
                            )
                            .accessibilityLabel("Starting latitude")
                        }
                        GridRow {
                            Text("Longitude")
                                .font(DesignToken.Typography.field)
                                .foregroundStyle(DesignToken.Status.neutral)
                            DeferredNumericField(
                                value: longitudeBinding,
                                fractionDigits: 6,
                                width: 120,
                                onEditingChange: { nmeaManager.isEditingGPSCoordinates = $0 }
                            )
                            .accessibilityLabel("Starting longitude")
                        }
                    }
                    Divider().padding(.vertical, DesignToken.Spacing.stacked)
                    GPSMapSelectorView(selectedCoordinate: selectedCoordinateBinding)
                }
                .disabled(!nmeaManager.sensorToggles.hasGPS)

                if !nmeaManager.sensorToggles.hasGPS {
                    SensorEnablePrompt(
                        message: "GPS is off. Enable GPS to edit position and map starting coordinates.",
                        actionTitle: "Enable GPS"
                    ) {
                        nmeaManager.sensorToggles.hasGPS = true
                    }
                }
            }
        }
    }
}
