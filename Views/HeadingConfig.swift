//
//  CompassView.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 16.06.25.
//

import SwiftUI

struct HeadingConfig: View {
    
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {
        GroupBox(label: Label("Compass Setup", systemImage: "safari")) {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("", isOn: $nmeaManager.sendHeading)
                        .toggleStyle(.switch)
                    Text("HDG")
                    HeadingSliderView(
                        centerValue: $nmeaManager.heading.centerValue,
                        offset: $nmeaManager.heading.randomOffset
                    )
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
    HeadingConfig(nmeaManager: NMEASimulator())
}

struct HeadingSliderView: View {
    @Binding var centerValue: Double
    @Binding var offset: Double
    
    var body: some View {
        HStack(spacing: 12) {
            
            CustomSlider(value: $centerValue, range: 0...360)
                .frame(minWidth: 150, maxWidth: .infinity)
                .tint(Color.red)
            
            TextField("°", value: $centerValue, format: .number.precision(.fractionLength(0)))
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
            
            Stepper("±\(Int(offset))°", value: $offset, in: 0...45, step: 1)
            //.labelsHidden()
                .frame(width: 70)
                .monospacedDigit()
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal)
    }
}
