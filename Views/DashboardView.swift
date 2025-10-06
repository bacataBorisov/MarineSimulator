//  DashboardView.swift
//  NMEASimulator

import SwiftUI
import MapKit

struct DashboardView: View {
    @Environment(NMEASimulator.self) private var nmeaManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Transmission Status
                GroupBox(label: Label("Status", systemImage: "dot.radiowaves.left.and.right")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(nmeaManager.isTransmitting ? "Transmitting" : "Idle",
                              systemImage: nmeaManager.isTransmitting ? "checkmark.circle.fill" : "pause.circle")
                            .foregroundStyle(nmeaManager.isTransmitting ? .green : .gray)

                        HStack {
                            Label("IP Address: \(nmeaManager.host)", systemImage: "network")
                            Label("Port: \(nmeaManager.port)", systemImage: "number")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                // Live Values
                GroupBox(label: Label("Live Readings", systemImage: "waveform.path.ecg")) {
                    Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            LabelText("HDG")
                            ValueText(FormatKit.formattedValue(nmeaManager.heading.value, decimals: 0))
                            LabelText("SOG")
                            ValueText(FormatKit.formattedValue(nmeaManager.gps.speedOverGround, decimals: 1))
                        }
                        GridRow {
                            LabelText("AWA")
                            ValueText(nmeaManager.formattedAWA)
                            LabelText("AWS")
                            ValueText(nmeaManager.formattedAWS)
                        }
                        GridRow {
                            LabelText("TWD")
                            ValueText(nmeaManager.formattedTWD)
                            LabelText("TWS")
                            ValueText(nmeaManager.formattedTWS)
                        }
                        GridRow {
                            LabelText("Depth")
                            ValueText(nmeaManager.formattedDepth)
                            LabelText("Speed")
                            ValueText(nmeaManager.formattedSpeed)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                }

                // Map Preview (optional)
                GroupBox(label: Label("Position", systemImage: "map")) {
                    BoatMapPreview(coordinate: CLLocationCoordinate2D(latitude: nmeaManager.gps.latitude,
                                                                     longitude: nmeaManager.gps.longitude))
                    .frame(height: 150)
                }
            }
            .padding()
        }
    }
}

#Preview {
    DashboardView().environment(NMEASimulator())
}