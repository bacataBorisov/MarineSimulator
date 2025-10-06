//
//  WindRawControlView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 23.06.25.
//
//
//
//  MARK: - Range values can be changed globally in Constants

import SwiftUI

struct WindRawControlView: View {
    
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        GroupBox(label: Label("Wind Control", systemImage: "wind")) {
            HStack() {
                Toggle("", isOn: $nmeaManager.sensorToggles.hasAnemometer)
                    .toggleStyle(.switch)
                
                Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {

                        ControlSliderView(value: $nmeaManager.twd, title: "True Wind Direction", precision: 0, sliderRange: SimulatedValueType.windDirection.defaultRange)
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(4)
                    }
                    GridRow {
                        ControlSliderView(value: $nmeaManager.tws, title: "True Wind Speed", unit: "knots", precision: 1, sliderRange: SimulatedValueType.windSpeed.defaultRange)
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(4)
                    }
                }

            }
        }
        .padding()
        .textFieldStyle(.roundedBorder)    }
    
}

#Preview{
    
    WindRawControlView(nmeaManager: NMEASimulator())
}
