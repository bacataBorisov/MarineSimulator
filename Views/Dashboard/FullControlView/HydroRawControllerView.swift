//
//  HydroRawControlView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 25.06.25.
//

import SwiftUI

struct HydroRawControllerView: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {
        GroupBox(label: Label("Hydro", systemImage: "drop")) {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("", isOn: $nmeaManager.sensorToggles.hasSpeedLog)
                        .toggleStyle(.switch)
                    ControlSliderView(value: $nmeaManager.speed, title: "Speed Through Water", unit: "knots", precision: 2, sliderRange: SimulatedValueType.speedLog.defaultRange)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(4)
                }
                GridRow {
                    Toggle("", isOn: $nmeaManager.sensorToggles.hasEchoSounder)
                        .toggleStyle(.switch)
                    ControlSliderView(value: $nmeaManager.depth, title: "Depth", unit: "mtrs", precision: 0, sliderRange: SimulatedValueType.depth.defaultRange)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(4)
                }
                GridRow {
                    Toggle("", isOn: $nmeaManager.sensorToggles.hasWaterTempSensor)
                        .toggleStyle(.switch)
                    ControlSliderView(value: $nmeaManager.seaTemp, title: "Sea Water Temperature", unit: "°C", precision: 1, sliderRange: SimulatedValueType.seaTemp.defaultRange)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(4)
                }
            }
        }
        .padding()
        .textFieldStyle(.roundedBorder)
    }
}

#Preview {
    HydroRawControllerView(nmeaManager: NMEASimulator())
}
