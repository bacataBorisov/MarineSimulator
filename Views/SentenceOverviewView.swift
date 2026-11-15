import SwiftUI

struct SentenceOverviewView: View {
    @Bindable var nmeaManager: NMEASimulator

    private let columns = [
        GridItem(.adaptive(minimum: 84), spacing: DesignToken.Spacing.row)
    ]

    var body: some View {
        PageContainer(maxWidth: ResponsiveLayout.adaptivePageMaxWidth) {
            SetupColumns {
                summaryBanner
                windCard
                atmosphereCard
                headingCard
                gpsCard
                hydroCard
            } wide: {
                summaryBanner
                HStack(alignment: .top, spacing: ResponsiveLayout.configurationGutter) {
                    VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
                        windCard
                        atmosphereCard
                        headingCard
                    }
                    .frame(maxWidth: ResponsiveLayout.configurationCardMaximum, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
                        gpsCard
                        hydroCard
                    }
                    .frame(maxWidth: ResponsiveLayout.configurationCardMaximum, alignment: .topLeading)
                }
            }
        }
    }

    private var summaryBanner: some View {
        Text("Click any sentence to enable or disable output. Amber indicates the sentence is enabled, but a required sensor in Simulation is turned off.")
            .font(DesignToken.Typography.supporting)
            .foregroundStyle(DesignToken.Status.neutral)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var windCard: some View {
        sentenceCard(
            title: "Wind",
            sentences: [
                SentenceControl(label: "MWV", isEnabled: $nmeaManager.sentenceToggles.shouldSendMWV, sendable: nmeaManager.sensorToggles.hasAnemometer),
                SentenceControl(label: "MWD", isEnabled: $nmeaManager.sentenceToggles.shouldSendMWD, sendable: nmeaManager.sensorToggles.hasAnemometer && nmeaManager.hasTrueHeading && nmeaManager.hasBoatSpeed),
                SentenceControl(label: "VPW", isEnabled: $nmeaManager.sentenceToggles.shouldSendVPW, sendable: nmeaManager.sensorToggles.hasAnemometer && nmeaManager.hasTrueHeading && nmeaManager.hasBoatSpeed)
            ]
        )
    }

    private var atmosphereCard: some View {
        sentenceCard(
            title: "Atmosphere",
            sentences: [
                SentenceControl(label: "MDA", isEnabled: $nmeaManager.sentenceToggles.shouldSendMDA, sendable: nmeaManager.hasAtmosphericSensor),
                SentenceControl(label: "XDR", isEnabled: $nmeaManager.sentenceToggles.shouldSendXDR, sendable: nmeaManager.hasAtmosphericSensor)
            ]
        )
    }

    private var headingCard: some View {
        sentenceCard(
            title: "Heading",
            sentences: [
                SentenceControl(label: "HDG", isEnabled: $nmeaManager.sentenceToggles.shouldSendHDG, sendable: nmeaManager.sensorToggles.hasCompass),
                SentenceControl(label: "HDT", isEnabled: $nmeaManager.sentenceToggles.shouldSendHDT, sendable: nmeaManager.sensorToggles.hasGyro),
                SentenceControl(label: "ROT", isEnabled: $nmeaManager.sentenceToggles.shouldSendROT, sendable: nmeaManager.sensorToggles.hasGyro)
            ]
        )
    }

    private var gpsCard: some View {
        sentenceCard(
            title: "GPS",
            sentences: [
                SentenceControl(label: "RMC", isEnabled: $nmeaManager.sentenceToggles.shouldSendRMC, sendable: nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "GGA", isEnabled: $nmeaManager.sentenceToggles.shouldSendGGA, sendable: nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "VTG", isEnabled: $nmeaManager.sentenceToggles.shouldSendVTG, sendable: nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "GLL", isEnabled: $nmeaManager.sentenceToggles.shouldSendGLL, sendable: nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "GSA", isEnabled: $nmeaManager.sentenceToggles.shouldSendGSA, sendable: nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "GSV", isEnabled: $nmeaManager.sentenceToggles.shouldSendGSV, sendable: nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "ZDA", isEnabled: $nmeaManager.sentenceToggles.shouldSendZDA, sendable: nmeaManager.sensorToggles.hasGPS)
            ]
        )
    }

    private var hydroCard: some View {
        sentenceCard(
            title: "Hydro",
            sentences: [
                SentenceControl(label: "DBT", isEnabled: $nmeaManager.sentenceToggles.shouldSendDBT, sendable: nmeaManager.sensorToggles.hasEchoSounder),
                SentenceControl(label: "DPT", isEnabled: $nmeaManager.sentenceToggles.shouldSendDPT, sendable: nmeaManager.sensorToggles.hasEchoSounder && abs(nmeaManager.depthOffsetMeters) <= 99),
                SentenceControl(label: "MTW", isEnabled: $nmeaManager.sentenceToggles.shouldSendMTW, sendable: nmeaManager.sensorToggles.hasWaterTempSensor),
                SentenceControl(label: "VHW", isEnabled: $nmeaManager.sentenceToggles.shouldSendVHW, sendable: nmeaManager.sensorToggles.hasSpeedLog && nmeaManager.hasTrueHeading),
                SentenceControl(label: "VBW", isEnabled: $nmeaManager.sentenceToggles.shouldSendVBW, sendable: nmeaManager.sensorToggles.hasSpeedLog || nmeaManager.sensorToggles.hasGPS),
                SentenceControl(label: "VLW", isEnabled: $nmeaManager.sentenceToggles.shouldSendVLW, sendable: nmeaManager.sensorToggles.hasSpeedLog)
            ]
        )
    }

    private func sentenceCard(title: String, sentences: [SentenceControl]) -> some View {
        SettingsCard(title: title) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DesignToken.Spacing.row) {
                ForEach(sentences) { status in
                    SentenceOverviewPill(control: status)
                }
            }
        }
    }
}

private struct SentenceControl: Identifiable {
    let label: String
    let isEnabled: Binding<Bool>
    let sendable: Bool

    var id: String { label }
}

private struct SentenceOverviewPill: View {
    let control: SentenceControl

    private var tint: Color {
        if control.isEnabled.wrappedValue && control.sendable {
            return DesignToken.Status.success.opacity(0.20)
        }
        if control.isEnabled.wrappedValue && !control.sendable {
            return DesignToken.Status.warning.opacity(0.20)
        }
        return DesignToken.Status.neutral.opacity(0.12)
    }

    private var stroke: Color {
        if control.isEnabled.wrappedValue && control.sendable {
            return DesignToken.Status.success.opacity(0.45)
        }
        if control.isEnabled.wrappedValue && !control.sendable {
            return DesignToken.Status.warning.opacity(0.45)
        }
        return DesignToken.Separator.standard.opacity(0.35)
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
                .padding(.horizontal, DesignToken.Spacing.inset)
                .padding(.vertical, DesignToken.Spacing.related)
                .background(tint, in: RoundedRectangle(cornerRadius: DesignToken.Radius.compactCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignToken.Radius.compactCard, style: .continuous)
                        .stroke(stroke)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
