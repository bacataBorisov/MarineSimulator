//
//  CompassView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

import SwiftUI
import MapKit

struct GPSConfig: View {
    @Bindable var nmeaManager: NMEASimulator
    @State private var latitudeInput: String = ""
    @State private var longitudeInput: String = ""
    
    var body: some View {
        GroupBox(label: Label("GPS Simulator", systemImage: "location.circle")) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Toggle("Send GPS", isOn: $nmeaManager.sendGPS)
                        .toggleStyle(.switch)
                        .gridCellColumns(2)
                }
                
                Divider().gridCellUnsizedAxes(.horizontal)
                
                GridRow {
                    Text("Latitude")
                        .font(.caption)
                    Text("Longitude")
                        .font(.caption)
                    EmptyView()
                }
                
                GridRow {
                    TextField("Latitude", text: $latitudeInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            updateGPSFromInputs()
                        }
                    
                    TextField("Longitude", text: $longitudeInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            updateGPSFromInputs()
                        }
                }
            }
            .onChange(of: nmeaManager.gps.latitude) {
                syncInputsWithGPS()
            }
            .onChange(of: nmeaManager.gps.longitude) {
                syncInputsWithGPS()
            }
            .onAppear {
                syncInputsWithGPS()
            }
        }//END OF GROUPBOX
        .padding()
        
        
    }
    
    private func syncInputsWithGPS() {
        latitudeInput = String(format: "%.5f", nmeaManager.gps.latitude)
        longitudeInput = String(format: "%.5f", nmeaManager.gps.longitude)
    }
    
    private func updateGPSFromInputs() {
        if let lat = Double(latitudeInput), let lon = Double(longitudeInput) {
            var updated = nmeaManager.gps
            updated.latitude = lat
            updated.longitude = lon
            nmeaManager.gps = updated
        }
    }
}

#Preview {
    GPSConfig(nmeaManager: NMEASimulator())
}

