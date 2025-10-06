import Foundation
import SwiftUI

struct HydroConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {
        GroupBox(label: Label("Hydro Data", systemImage: "water.waves")) {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                
                GridRow {
                    Toggle("", isOn: $nmeaManager.sendSpeed)
                        .gridColumnAlignment(.center)
                        .toggleStyle(.switch)
                    Text("Speed")
                        .gridColumnAlignment(.leading)
                    TextField("min", value: $nmeaManager.speed.min, format: .number)
                    Stepper("", value: $nmeaManager.speed.min, step: 0.5)
                    TextField("max", value: $nmeaManager.speed.max, format: .number)
                    Stepper("", value: $nmeaManager.speed.max, step: 0.5)
                }
                
                GridRow {
                    Toggle("", isOn: $nmeaManager.sendDepth)
                        .gridColumnAlignment(.center)
                        .toggleStyle(.switch)
                    Text("Depth")
                    TextField("min", value: $nmeaManager.depth.min, format: .number)
                    Stepper("", value: $nmeaManager.depth.min, step: 2)
                    TextField("max", value: $nmeaManager.depth.max, format: .number)
                    Stepper("", value: $nmeaManager.depth.max, step: 2)
                }
                
                GridRow() {
                    Toggle("", isOn: $nmeaManager.sendTemp)
                        .gridColumnAlignment(.center)
                        .toggleStyle(.switch)
                    Text("Sea Water Temp")
                    TextField("min", value: $nmeaManager.seaTemp.min, format: .number)
                    Stepper("", value: $nmeaManager.seaTemp.min, step: 0.2)
                    TextField("max", value: $nmeaManager.seaTemp.max, format: .number)
                    Stepper("", value: $nmeaManager.seaTemp.max, step: 0.2)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding()
        
    }
}

#Preview {
    HydroConfig(nmeaManager: NMEASimulator())
}
