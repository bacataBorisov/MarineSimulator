import SwiftUI

struct ConnectionView: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.record(.connection)
        #endif
        PageContainer(maxWidth: ResponsiveLayout.adaptivePageMaxWidth) {
            SetupColumns {
                connectionHealth
                outputsOffNotice
                transmission
                Divider()
                primaryOutput
                additionalOutputs
            } wide: {
                connectionHealth
                outputsOffNotice
                transmission
                Divider()
                HStack(alignment: .top, spacing: ResponsiveLayout.configurationGutter) {
                    primaryOutput
                        .frame(maxWidth: ResponsiveLayout.configurationCardMaximum, alignment: .topLeading)
                    additionalOutputs
                        .frame(maxWidth: ResponsiveLayout.configurationCardMaximum, alignment: .topLeading)
                }
            }
            .background(alignment: .topLeading) {
                RetainedDestinationMarker(page: .connection)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var connectionHealth: some View {
        ConnectionHealthBanner(nmeaManager: nmeaManager)
    }

    @ViewBuilder
    private var outputsOffNotice: some View {
        if nmeaManager.outputEndpoints.allSatisfy({ !$0.isEnabled }) {
            Label("All outputs are off — Start still runs the simulation, but nothing is sent.", systemImage: "exclamationmark.triangle")
                .font(DesignToken.Typography.status)
                .foregroundStyle(DesignToken.Status.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignToken.Spacing.inset)
                .background(
                    DesignToken.Status.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DesignToken.Radius.status)
                )
                .accessibilityIdentifier(SetupSection.connectionWarning.rawValue)
        }
    }

    private var primaryOutput: some View {
        SettingsCard(title: "Primary Output", accessibilityID: SetupSection.primaryOutput.rawValue) {
                    if let primaryID = nmeaManager.outputEndpoints.first?.id,
                       let primaryIndex = nmeaManager.outputEndpoints.firstIndex(where: { $0.id == primaryID }) {
                        EndpointEditorView(
                            nmeaManager: nmeaManager,
                            endpoint: $nmeaManager.outputEndpoints[primaryIndex],
                            isPrimary: true
                        )
                    }
                }
    }

    private var transmission: some View {
        ConnectionTransmissionCard(nmeaManager: nmeaManager)
    }

    private var additionalOutputs: some View {
        AdditionalOutputsSection(nmeaManager: nmeaManager)
    }
}

private struct ConnectionTransmissionCard: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        SettingsCard(title: "Transmission", accessibilityID: SetupSection.transmission.rawValue) {
            TimerStatusText(nmeaManager: nmeaManager)

            Toggle("Enable Timer", isOn: $nmeaManager.isTimerSelected)
                .toggleStyle(.switch)
                .controlSize(.regular)
                .accessibilityIdentifier("Enable Timer")

            HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.card) {
                Text("Send Interval (s)")
                    .font(DesignToken.Typography.field)
                    .frame(width: 140, alignment: .leading)
                Stepper(value: $nmeaManager.interval, in: 0.1...10, step: 0.1) {
                    SendIntervalText(nmeaManager: nmeaManager)
                }
                .accessibilityLabel("Send interval in seconds")
                .disabled(!nmeaManager.isTimerSelected)
                Spacer(minLength: 0)
            }

            Text("Fallback sentence interval and stagger window. Sensor redraw stays at 1 s. Profile sentence rates are separate.")
                .font(DesignToken.Typography.help)
                .foregroundStyle(DesignToken.Status.neutral)
        }
    }
}

/// Reads the timer mode in this body. It stays a direct child of the Transmission card.
private struct TimerStatusText: View {
    @Bindable var nmeaManager: NMEASimulator
    #if DEBUG
    @Environment(\.settingsCardIdentity) private var settingsCardIdentity
    #endif

    var body: some View {
        let status = nmeaManager.isTimerSelected
            ? "Continuous timer mode is active."
            : "Timer disabled: Start sends one burst only."
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.noteTimerStatus(status, card: settingsCardIdentity)
        #endif
        Text(status)
            .font(DesignToken.Typography.supporting)
            .foregroundStyle(nmeaManager.isTimerSelected ? DesignToken.Status.neutral : DesignToken.Status.warning)
            .accessibilityLabel(status)
            .accessibilityIdentifier("Timer Status")
    }
}

/// Reads the send interval in this body. The surrounding stepper remains the editor.
private struct SendIntervalText: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        let label = String(format: "%.1f", nmeaManager.interval)
        #if DEBUG
        let _ = RetainedDestinationBodyProbe.noteInterval(label)
        #endif
        Text(label)
            .monospacedDigit()
            .frame(minWidth: 44, alignment: .trailing)
            .accessibilityIdentifier("Send Interval")
    }
}

/// Reads the endpoint array in this body. `SetupColumns` only places this view.
/// A `ForEach` built inside the column closure does not subscribe to later inserts or removals.
private struct AdditionalOutputsSection: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        let endpoints = nmeaManager.outputEndpoints
        SettingsCard(title: "Additional Outputs", accessibilityID: SetupSection.additionalOutputs.rawValue) {
            Text("Add destinations for multi-device testing (e.g. iPhone + iPad unicast).")
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)

            ForEach(Array(endpoints.enumerated()), id: \.element.id) { index, _ in
                if index > 0 {
                    EndpointEditorView(
                        nmeaManager: nmeaManager,
                        endpoint: $nmeaManager.outputEndpoints[index],
                        isPrimary: false
                    )
                    .padding(DesignToken.Spacing.header)
                    .background(
                        DesignToken.Surface.nested,
                        in: RoundedRectangle(cornerRadius: DesignToken.Radius.compactCard, style: .continuous)
                    )
                }
            }

            HStack {
                Spacer()
                Button {
                    nmeaManager.addOutputEndpoint()
                } label: {
                    Label("Add Output", systemImage: "plus")
                }
                .accessibilityIdentifier("Add Output")
            }
        }
    }
}

#Preview {
    ConnectionView(nmeaManager: NMEASimulator())
        .frame(width: 1160, height: 820)
}
