//

import SwiftUI

struct HeadingRawControllerView: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {
        GroupBox(label: Label("Heading", systemImage: "safari")) {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("", isOn: $nmeaManager.sensorToggles.hasCompass)
                        .toggleStyle(.switch)
                    ControlSliderView(value: $nmeaManager.heading, title: "Magnetic Compass", precision: 0, sliderRange: SimulatedValueType.magneticCompass.defaultRange)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(4)
                }
                GridRow {
                    Toggle("", isOn: $nmeaManager.sensorToggles.hasGyro)
                        .toggleStyle(.switch)
                    ControlSliderView(value: $nmeaManager.gyroHeading, title: "Gyro Compass", precision: 1, sliderRange: SimulatedValueType.gyroCompass.defaultRange)
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
    HeadingRawControllerView(nmeaManager: NMEASimulator())
}
