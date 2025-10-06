import SwiftUI

struct ConfigurationView: View {

    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .center, spacing: 3 * UIConstants.spacing) {
                    
                    // MARK: - Network + Transmission (Full Width)
                    GroupBox(label: Label("Network Settings", systemImage: "network")) {
                        Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("IP")
                                TextField("IP Address", text: $nmeaManager.ip)
                                    .gridColumnAlignment(.leading)
                                Text("Port")
                                TextField("Port", value: $nmeaManager.port, formatter: FormatKit.plainNumberFormatter)
                                Text("Talker ID")
                                TextField("Talker ID", text: $nmeaManager.talkerID)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)

                    GroupBox(label: Label("Transmission", systemImage: "antenna.radiowaves.left.and.right")) {
                        Grid(horizontalSpacing: 3 * UIConstants.spacing, verticalSpacing: 3 * UIConstants.spacing) {
                            GridRow {
                                Toggle("Enable Timer", isOn: $nmeaManager.isTimerSelected)
                                    .toggleStyle(.switch)
                                    .gridColumnAlignment(.leading)
                                Text("Send Interval (s)")
                                Stepper(value: $nmeaManager.interval, in: 0.1...10, step: 0.1) {
                                    Text(String(format: "%.1f", nmeaManager.interval))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // MARK: - First Row: Navigation + Hydro + Environmental (3 Columns)
                    HStack(alignment: .top, spacing: UIConstants.spacing) {
                        sensorBox(
                            title: "Navigation Instruments",
                            icon: "safari",
                            toggles: [
                                ("Anemometer", $nmeaManager.sensorToggles.hasAnemometer),
                                ("Magnetic Compass", $nmeaManager.sensorToggles.hasCompass),
                                ("Gyro Compass", $nmeaManager.sensorToggles.hasGyro)
                            ]
                        )

                        sensorBox(
                            title: "Hydro Sensors",
                            icon: "drop.triangle",
                            toggles: [
                                ("Echo Sounder", $nmeaManager.sensorToggles.hasEchoSounder),
                                ("Speed Log", $nmeaManager.sensorToggles.hasSpeedLog),
                                ("Water Temperature", $nmeaManager.sensorToggles.hasWaterTempSensor)
                            ]
                        )

                        sensorBox(
                            title:"Environmental Sensors",
                            icon: "thermometer.sun.circle",
                            toggles: [
                                ("Air Temperature", $nmeaManager.sensorToggles.hasAirTempSensor),
                                ("Humidity", $nmeaManager.sensorToggles.hasHumidtySensor),
                                ("Barometer", $nmeaManager.sensorToggles.hasBarometer)
                            ]
                        )
                        
                    }
                    .padding(.horizontal)


                    // MARK: - Second Row: Positioning + Satellite (2 Columns)
                    HStack(alignment: .top, spacing: UIConstants.spacing) {
                        sensorBox(
                            title: "Positioning",
                            icon: "location",
                            toggles: [
                                ("GPS", $nmeaManager.sensorToggles.hasGPS),
                                ("AIS", $nmeaManager.sensorToggles.hasAIS)
                            ]
                        )

                        sensorBox(
                            title: "Satellite & Communication",
                            icon: "antenna.radiowaves.left.and.right.circle",
                            toggles: [
                                ("GNSS Receiver", $nmeaManager.sensorToggles.shouldSendGNSS),
                                ("DSC Radio / MMSI", $nmeaManager.sensorToggles.shouldSendDSC)
                            ]
                        )
                    }
                    .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical
                )
            }
        }
    }

    // MARK: - Sensor Box View
    @ViewBuilder
    private func sensorBox(title: String, icon: String, toggles: [(String, Binding<Bool>)]) -> some View {
        GroupBox(label: Label(title, systemImage: icon)) {
            VStack(spacing: UIConstants.spacing * 2) {
                ForEach(toggles.indices, id: \.self) { i in
                    ViewKit.ToggleRowWithInfo(
                        toggles[i].0,
                        isOn: toggles[i].1
                        
                        //MARK: - I need to see if it is useful!!
                        //showInfo: .constant(false) // or bind to a real state if needed
                        //infoView: { AnyView(EmptyView()) } // you can provide real help views here
                    )
                }
            }
            .toggleStyle(.switch)
            .padding()
        }
    }
}

#Preview {
    ConfigurationView(nmeaManager: NMEASimulator())
        .frame(width: 900, height: 600)
}
