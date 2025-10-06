//
//  HeadingConfig.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 23.06.25.
//


    //
    //  CompassView.swift
    //  NMEASimulator
    //
    //  Created by Vasil Borisov on 16.06.25.
    //

    import SwiftUI

struct HeadingRawControllerView: View {
        
        @Bindable var nmeaManager: NMEASimulator
        
        var body: some View {
            GroupBox(label: Label("Compass Setup", systemImage: "safari")) {
                Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Toggle("", isOn: $nmeaManager.shouldSendCompass)
                            .toggleStyle(.switch)
                        Text("HDG")
                        MetricHeadingControlView(heading: $nmeaManager.heading, title: "Heading", precision: 0)
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

struct MetricHeadingControlView: View {
    
    @Binding var heading: Metric
    var title: String = "Heading"
    var unit: String = "°"
    var precision: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label(title, systemImage: "slider.horizontal.3")
                .font(.headline)

            // Center + Offset Controls
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("")
                        .font(.subheadline)
                    TextField("", value: $heading.centerValue, format: .number.precision(.fractionLength(precision)))
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("±")
                    Stepper("\(heading.randomOffset.formatted(.number.precision(.fractionLength(precision))))", value: $heading.randomOffset, in: 0...180, step: 1)
                        .frame(width: 80)
                        .monospacedDigit()
                }
            }

            // Slider
            CustomSlider(value: $heading.centerValue, range: 0...359)

            // Output
            Text("Output: \(heading.value?.formatted(.number.precision(.fractionLength(precision))) ?? "-") \(unit)")
                .font(.footnote)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
