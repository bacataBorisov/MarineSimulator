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
    var isCompassActive: Bool = true

    var body: some View {
        @Bindable var nmea = nmea

        VStack(alignment: .leading, spacing: AppChrome.railSectionSpacing) {
            WindCompass(isActive: isCompassActive)
                .padding(6)
                .background(AppChrome.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            RailDivider()

            RailSection("Wind") {
                MetricGrid(columns: 2) {
                    MetricRow(label: "TWD", value: deg(nmea.calculatedTWD))
                    MetricRow(label: "TWD Dir", value: textOrPlaceholder(nmea.calculatedTWDCompassPoint))
                    MetricRow(label: "TWS", value: kn(nmea.calculatedTWS))
                    MetricRow(label: "Gust", value: kn(nmea.displayedWindGustSpeed))
                    MetricRow(label: "AWA", value: deg(nmea.calculatedAWA))
                    MetricRow(label: "AWS", value: kn(nmea.calculatedAWS))
                    MetricRow(label: "TWA rel", value: deg(nmea.calculatedTWA))
                    MetricRow(label: "AWD abs", value: deg(nmea.calculatedAWD))
                }
            }

            RailDivider()

            RailSection("Heading / Speed") {
                MetricGrid(columns: 2) {
                    MetricRow(label: "HDG (mag)", value: deg(nmea.heading.value))
                    MetricRow(label: "COG", value: deg(nmea.gpsData.courseOverGround))
                    MetricRow(label: "SOG", value: kn(nmea.gpsData.speedOverGround))
                    MetricRow(label: "Boat SPD", value: kn(nmea.speed.value))
                }
            }

            RailDivider()

            RailSection("Hydro") {
                MetricGrid(columns: 2) {
                    MetricRow(label: "Depth", value: meters(nmea.depth.value))
                    MetricRow(label: "Sea Temp", value: degC(nmea.displayedSeaTemperature))
                }
            }

            RailDivider()

            RailSection("Atmosphere") {
                MetricGrid(columns: 2) {
                    MetricRow(label: "Air Temp", value: degC(nmea.displayedAirTemperature))
                    MetricRow(label: "Humidity", value: percent(nmea.displayedRelativeHumidity))
                    MetricRow(label: "Barometer", value: hectopascals(nmea.displayedAirPressure))
                }
            }

            RailDivider()

            RailSection("GPS") {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel("Lat", text: coord(nmea.gpsData.latitude))
                    MonoLabel("Lon", text: coord(nmea.gpsData.longitude))
                    MonoLabel("Fix", text: nmea.sensorToggles.hasGPS ? "A" : "--")
                }
            }
        }
        .padding(AppChrome.railPadding)
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
        .padding(10)
        .background(AppChrome.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        }
        .accessibilityElement(children: .combine)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppChrome.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
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
    return String(format: "%.1f °C", v)
}

@inline(__always) func coord(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.5f", v)
}

@inline(__always) func percent(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.0f %%", v)
}

@inline(__always) func hectopascals(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.1f hPa", v)
}

@inline(__always) func textOrPlaceholder(_ value: String?) -> String {
    value ?? "--"
}
