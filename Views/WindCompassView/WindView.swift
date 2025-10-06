// WindView.swift
// Extending with live-calculated AWA, AWS, AWD, TWA

import SwiftUI

struct WindView: View {
    @Bindable var nmeaManager: NMEASimulator
    
    var body: some View {

            GroupBox(label: Label("Wind Data", systemImage: "wind.snow")) {
                Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                    
                    GridRow {
                        Toggle("", isOn: $nmeaManager.sendTWD)
                            .gridColumnAlignment(.center)
                            .toggleStyle(.switch)
                        Text("TWD")
                        TextField("min", value: $nmeaManager.twd.min, format: .number)
                        Stepper("", value: $nmeaManager.twd.min, step: 5)
                        TextField("max", value: $nmeaManager.twd.max, format: .number)
                        Stepper("", value: $nmeaManager.twd.max, step: 5)
                    }
                    
                    GridRow {
                        Toggle("", isOn: $nmeaManager.sendTWS)
                            .gridColumnAlignment(.center)
                            .toggleStyle(.switch)
                        Text("TWS")
                        TextField("min", value: $nmeaManager.tws.min, format: .number)
                        Stepper("", value: $nmeaManager.tws.min, step: 1)
                        TextField("max", value: $nmeaManager.tws.max, format: .number)
                        Stepper("", value: $nmeaManager.tws.max, step: 1)
                    }
                    
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
                    
                    Divider().gridCellUnsizedAxes(.horizontal)
                    
                    GridRow {
                        LabelText("AWA")
                        ValueText(nmeaManager.formattedAWA)
                        LabelText("AWS")
                        ValueText(nmeaManager.formattedAWS)
                        LabelText("AWD")
                        ValueText(nmeaManager.formattedAWD)
                    }
                    
                    GridRow {
                        LabelText("TWA")
                        ValueText(nmeaManager.formattedTWA)
                        LabelText("TWS")
                        ValueText(nmeaManager.formattedTWS)
                        LabelText("TWD")
                        ValueText(nmeaManager.formattedTWD)
                    }
                    GridRow {
                        LabelText("HDG")
                        ValueText(FormatKit.formattedValue(nmeaManager.heading.value, decimals: 0))
                        
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            .padding()
        
    }
}

// Reusable label styling
@ViewBuilder
public func LabelText(_ text: String) -> some View {
    Text(text)
        .fontWeight(.medium)
        .frame(width: 40, alignment: .trailing)
}

// Reusable fixed-width value styling
@ViewBuilder
public func ValueText(_ value: String) -> some View {
    Text(value)
        .frame(width: 50, alignment: .trailing)
        .monospacedDigit()
        .font(.system(.body, design: .monospaced))
}

#Preview {
    WindView(nmeaManager: NMEASimulator())
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
