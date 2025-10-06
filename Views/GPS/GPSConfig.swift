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

    
    var body: some View {
        GeometryReader { _ in
            HStack(alignment: .top, spacing: UIConstants.spacing * 2) {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    GPSSentencesSection(
                        nmeaManager: nmeaManager,
                        shouldSendRMC: $nmeaManager.sentenceToggles.shouldSendRMC,
                        shouldSendGGA: $nmeaManager.sentenceToggles.shouldSendGGA,
                        shouldSendVTG: $nmeaManager.sentenceToggles.shouldSendVTG,
                        shouldSendGLL: $nmeaManager.sentenceToggles.shouldSendGLL,
                        shouldSendGSA: $nmeaManager.sentenceToggles.shouldSendGSA,
                        shouldSendGSV: $nmeaManager.sentenceToggles.shouldSendGSV,
                        shouldSendZDA: $nmeaManager.sentenceToggles.shouldSendZDA,
                        showRMC: $showRMC,
                        showGGA: $showGGA,
                        showVTG: $showVTG,
                        showGLL: $showGLL,
                        showGSA: $showGSA,
                        showGSV: $showGSV,
                        showZDA: $showZDA
                    )
                }
                .padding()
            }
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
    
    @Binding var showRMC: Bool
    @Binding var showGGA: Bool
    @Binding var showVTG: Bool
    @Binding var showGLL: Bool
    @Binding var showGSA: Bool
    @Binding var showGSV: Bool
    @Binding var showZDA: Bool
    
    
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
                }
            }
        )
    }
    
    var body: some View {
        GroupBox(label: Label("GPS Sentences", systemImage: "location")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                
                ViewKit.ToggleRowWithInfo(
                    "RMC - Recommended Minimum Navigation Info",
                    isOn: $shouldSendRMC,
                    showInfo: $showRMC,
                    infoView: { AnyView(RMCHelpView().font(.caption)) }
                )
                
                ViewKit.ToggleRowWithInfo(
                    "GGA - Fix Data",
                    isOn: $shouldSendGGA,
                    showInfo: $showGGA,
                    infoView: { AnyView(GGAHelpView().font(.caption)) }
                )
                
                ViewKit.ToggleRowWithInfo(
                    "VTG - Course and Speed Over Ground",
                    isOn: $shouldSendVTG,
                    showInfo: $showVTG,
                    infoView: { AnyView(VTGHelpView().font(.caption)) }
                )
                
                ViewKit.ToggleRowWithInfo(
                    "GLL - Geographic Position",
                    isOn: $shouldSendGLL,
                    showInfo: $showGLL,
                    infoView: { AnyView(GLLHelpView().font(.caption)) }
                )
                
                ViewKit.ToggleRowWithInfo(
                    "GSA - DOP and Active Satellites",
                    isOn: $shouldSendGSA,
                    showInfo: $showGSA,
                    infoView: { AnyView(GSAHelpView().font(.caption)) }
                )
                
                ViewKit.ToggleRowWithInfo(
                    "GSV - Satellites in View",
                    isOn: $shouldSendGSV,
                    showInfo: $showGSV,
                    infoView: { AnyView(GSVHelpView().font(.caption)) }
                )
                
                ViewKit.ToggleRowWithInfo(
                    "ZDA - Time and Date",
                    isOn: $shouldSendZDA,
                    showInfo: $showZDA,
                    infoView: { AnyView(ZDAHelpView().font(.caption)) }
                )
                
                if(!GPSSentencesSection.isGPSEnabled(nmeaManager)){
                    Text(UIStrings.Warnings.enableGPS)
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                        .padding(.leading, 4)
                }
                
            }
            .disabled(!nmeaManager.sensorToggles.hasGPS)
            .toggleStyle(.switch)
        }
        GroupBox(label: Label("Set Starting Coordinates", systemImage: "mappin.and.ellipse")) {
            VStack(alignment: .leading, spacing: UIConstants.spacing) {
                HStack {
                    Text("Latitude:")
                    TextField("", value: $nmeaManager.gpsData.latitude, formatter: FormatKit.decimalFormatter(fractionDigits: 6))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Longitude:")
                    TextField("", value: $nmeaManager.gpsData.longitude, formatter: FormatKit.decimalFormatter(fractionDigits: 6))
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
                Divider().padding(.vertical, 4)
                GPSMapSelectorView(selectedCoordinate: selectedCoordinateBinding)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }

    }
    static func isGPSEnabled(_ nmea: NMEASimulator) -> Bool {
        nmea.sensorToggles.hasGPS
    }
}


