//
//  SidebarContentConnected.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 6.10.25.
//


import SwiftUI
import MapKit

/// Replace the old placeholder `SidebarContent` with this:
struct TrailingSidePanel: View {
    @Environment(NMEASimulator.self) private var nmea

    var body: some View {
        // INSTRUMENTS
        GroupBox("Instruments") {
            VStack(alignment: .leading, spacing: 12) {
                // Replace these with your real instrument views
                // e.g. `AnemometerView(nmeaManager: nmea)` if required
                WindCompass()
                    //.frame(height: 140)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                
                // WIND METRICS
                GroupBox("Wind") {
                    MetricGrid(columns: 2) {
                        MetricRow(label: "TWD", value: deg(nmea.calculatedTWD))
                        MetricRow(label: "TWS", value: kn(nmea.calculatedTWS))
                        MetricRow(label: "AWA", value: deg(nmea.calculatedAWA))
                        MetricRow(label: "AWS", value: kn(nmea.calculatedAWS))
                        MetricRow(label: "TWA", value: deg(nmea.calculatedTWA))
                        MetricRow(label: "AWD", value: deg(nmea.calculatedAWD))
                    }
                }

                // HEADING & SPEED
                GroupBox("Heading / Speed") {
                    MetricGrid(columns: 2) {
                        MetricRow(label: "HDG (mag)", value: deg(nmea.heading.value))
                        MetricRow(label: "COG", value: deg(nmea.gpsData.courseOverGround))
                        MetricRow(label: "SOG", value: kn(nmea.gpsData.speedOverGround))
                        MetricRow(label: "Boat SPD", value: kn(nmea.speed.value))
                    }
                }

                // HYDRO
                GroupBox("Hydro") {
                    MetricGrid(columns: 2) {
                        MetricRow(label: "Depth", value: meters(nmea.depth.value))
                        MetricRow(label: "Sea Temp", value: degC(nmea.seaTemp.value))
                    }
                }

                // GPS
                GroupBox("GPS") {
                    VStack(alignment: .leading, spacing: 6) {
                        MonoLabel("Lat", text: coord(nmea.gpsData.latitude))
                        MonoLabel("Lon", text: coord(nmea.gpsData.longitude))
                        MonoLabel("Fix", text: "A") // adapt when you add real fix status
                    }
                    .padding(4)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }

                // OPTIONAL: quick sentence toggles (wire to your booleans)
                GroupBox("Sentence Output") {
                    HStack(spacing: 8) {
                        CapsuleToggle(label: "MWV", isOn: .constant(nmea.sentenceToggles.shouldSendMWV))
                        CapsuleToggle(label: "MWD", isOn: .constant(nmea.sentenceToggles.shouldSendMWD))
                        CapsuleToggle(label: "VPW", isOn: .constant(nmea.sentenceToggles.shouldSendVPW))
                        // If you want these to truly toggle your model, expose bindings, e.g.
                        // CapsuleToggle(label: "MWV", isOn: $nmea.sentenceToggles.shouldSendMWV)
                    }
                }
            }
        }
    }
}

//MARK: - These need to be moved to a different file but I forgot which one :)))

// Grid wrapper for a uniform 2-column metrics layout
struct MetricGrid<Content: View>: View {
    let columns: Int
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: max(columns,1)),
            spacing: 8
        ) {
            content
        }
        .padding(6)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(.white)
        }
    }
}

struct MonoLabel: View {
    let title: String
    let text: String
    init(_ title: String, text: String) {
        self.title = title; self.text = text
    }
    var body: some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(text).font(.system(.callout, design: .monospaced))
        }
    }
}

// Capsule-style toggle (you can later bind to your @Environment model)
struct CapsuleToggle: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isOn ? .green.opacity(0.25) : .white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tiny formatters

@inline(__always) func deg(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.0f°", v)
}

@inline(__always) func kn(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.1f kn", v)
}

@inline(__always) func meters(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.1f m", v)
}

@inline(__always) func degC(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.1f ℃", v)
}

@inline(__always) func coord(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.5f", v)
}
