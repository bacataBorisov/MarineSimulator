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

    private let sentenceColumns = [
        GridItem(.adaptive(minimum: 68), spacing: 8)
    ]

    var body: some View {
        @Bindable var nmea = nmea

        VStack(alignment: .leading, spacing: AppChrome.railSectionSpacing) {
            RailSection("Instruments", subtitle: "Live instrument state and sentence availability.") {
                WindCompass()
                    .padding(6)
                    .background(AppChrome.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            RailDivider()

            RailSection("Wind") {
                MetricGrid(columns: 2) {
                    MetricRow(label: "TWD", value: deg(nmea.calculatedTWD))
                    MetricRow(label: "TWS", value: kn(nmea.calculatedTWS))
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
                    MetricRow(label: "Sea Temp", value: degC(nmea.seaTemp.value))
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

            RailDivider()

            RailSection("Sentence Output", subtitle: "Click a sentence to enable or disable it instantly. Warning state means the sentence is enabled but currently blocked by dependencies.") {
                VStack(alignment: .leading, spacing: 12) {
                    sentenceGroup("Wind", sentences: [
                        sentenceControl("MWV", enabled: $nmea.sentenceToggles.shouldSendMWV, sendable: nmea.sensorToggles.hasAnemometer),
                        sentenceControl("MWD", enabled: $nmea.sentenceToggles.shouldSendMWD, sendable: nmea.sensorToggles.hasAnemometer && nmea.hasTrueHeading && nmea.hasBoatSpeed),
                        sentenceControl("VPW", enabled: $nmea.sentenceToggles.shouldSendVPW, sendable: nmea.sensorToggles.hasAnemometer && nmea.hasTrueHeading && nmea.hasBoatSpeed)
                    ])

                    sentenceGroup("Heading", sentences: [
                        sentenceControl("HDG", enabled: $nmea.sentenceToggles.shouldSendHDG, sendable: nmea.sensorToggles.hasCompass),
                        sentenceControl("HDT", enabled: $nmea.sentenceToggles.shouldSendHDT, sendable: nmea.sensorToggles.hasGyro),
                        sentenceControl("ROT", enabled: $nmea.sentenceToggles.shouldSendROT, sendable: nmea.sensorToggles.hasGyro)
                    ])

                    sentenceGroup("GPS", sentences: [
                        sentenceControl("RMC", enabled: $nmea.sentenceToggles.shouldSendRMC, sendable: nmea.sensorToggles.hasGPS),
                        sentenceControl("GGA", enabled: $nmea.sentenceToggles.shouldSendGGA, sendable: nmea.sensorToggles.hasGPS),
                        sentenceControl("VTG", enabled: $nmea.sentenceToggles.shouldSendVTG, sendable: nmea.sensorToggles.hasGPS),
                        sentenceControl("GLL", enabled: $nmea.sentenceToggles.shouldSendGLL, sendable: nmea.sensorToggles.hasGPS),
                        sentenceControl("GSA", enabled: $nmea.sentenceToggles.shouldSendGSA, sendable: nmea.sensorToggles.hasGPS),
                        sentenceControl("GSV", enabled: $nmea.sentenceToggles.shouldSendGSV, sendable: nmea.sensorToggles.hasGPS),
                        sentenceControl("ZDA", enabled: $nmea.sentenceToggles.shouldSendZDA, sendable: nmea.sensorToggles.hasGPS)
                    ])

                    sentenceGroup("Hydro", sentences: [
                        sentenceControl("DBT", enabled: $nmea.sentenceToggles.shouldSendDBT, sendable: nmea.sensorToggles.hasEchoSounder),
                        sentenceControl("DPT", enabled: $nmea.sentenceToggles.shouldSendDPT, sendable: nmea.sensorToggles.hasEchoSounder && abs(nmea.depthOffsetMeters) <= 99),
                        sentenceControl("MTW", enabled: $nmea.sentenceToggles.shouldSendMTW, sendable: nmea.sensorToggles.hasWaterTempSensor),
                        sentenceControl("VHW", enabled: $nmea.sentenceToggles.shouldSendVHW, sendable: nmea.sensorToggles.hasSpeedLog && nmea.hasTrueHeading),
                        sentenceControl("VBW", enabled: $nmea.sentenceToggles.shouldSendVBW, sendable: nmea.sensorToggles.hasSpeedLog || nmea.sensorToggles.hasGPS),
                        sentenceControl("VLW", enabled: $nmea.sentenceToggles.shouldSendVLW, sendable: nmea.sensorToggles.hasSpeedLog)
                    ])
                }
            }
        }
        .padding(AppChrome.railPadding)
    }

    private func sentenceControl(_ label: String, enabled: Binding<Bool>, sendable: Bool) -> SentenceControl {
        SentenceControl(label: label, isEnabled: enabled, sendable: sendable)
    }

    @ViewBuilder
    private func sentenceGroup(_ title: String, sentences: [SentenceControl]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: sentenceColumns, alignment: .leading, spacing: 8) {
                ForEach(sentences) { status in
                    SentencePill(control: status)
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
    }
}

private struct SentenceControl: Identifiable {
    let label: String
    let isEnabled: Binding<Bool>
    let sendable: Bool

    var id: String { label }
}

private struct SentencePill: View {
    let control: SentenceControl

    private var tint: Color {
        if control.isEnabled.wrappedValue && control.sendable {
            return AppColors.success.opacity(0.22)
        }

        if control.isEnabled.wrappedValue && !control.sendable {
            return AppColors.warning.opacity(0.22)
        }

        return .white.opacity(0.08)
    }

    private var stroke: Color {
        if control.isEnabled.wrappedValue && !control.sendable {
            return AppColors.warning.opacity(0.40)
        }

        return .white.opacity(0.08)
    }

    private var helpText: String {
        if control.isEnabled.wrappedValue && control.sendable {
            return "\(control.label) is enabled and currently sendable. Click to disable it."
        }

        if control.isEnabled.wrappedValue {
            return "\(control.label) is enabled in settings but blocked by missing sensor dependencies. Click to disable it."
        }

        return "\(control.label) is currently disabled. Click to enable it."
    }

    var body: some View {
        Button {
            control.isEnabled.wrappedValue.toggle()
        } label: {
            Text(control.label)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(stroke)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
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
