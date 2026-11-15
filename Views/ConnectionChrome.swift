import SwiftUI

// MARK: - Transport styling

extension TransportStatusLevel {
    var color: Color {
        switch self {
        case .idle: return DesignToken.Status.neutral
        case .connected: return DesignToken.Status.success
        case .warning: return DesignToken.Status.warning
        case .error: return DesignToken.Status.error
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "questionmark.circle"
        case .connected: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

enum PrimaryOutputSummary {
    static func label(for simulator: NMEASimulator) -> String {
        guard let primary = simulator.outputEndpoints.first else {
            return "Primary: not configured"
        }
        let name = primary.name.isEmpty ? "Primary" : primary.name
        if !primary.isEnabled {
            return "\(name): off"
        }
        let transport = primary.transport.rawValue.uppercased()
        if primary.transport == .udp, primary.isBroadcast {
            return "\(name): UDP broadcast :\(primary.port)"
        }
        return "\(name): \(transport) \(primary.host):\(primary.port)"
    }
}

// MARK: - Connection health banner

struct ConnectionHealthBanner: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        Group {
            if nmeaManager.isTransmitting {
                if let status = nmeaManager.latestTransportStatus {
                    Label(status.message, systemImage: status.level.systemImage)
                        .foregroundStyle(status.level.color)
                } else {
                    Label("Transmitting", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(DesignToken.Status.success)
                }
            } else if let status = nmeaManager.latestTransportStatus, status.level != .idle {
                Label(status.message, systemImage: status.level.systemImage)
                    .foregroundStyle(status.level.color)
            } else {
                Label("Not sending — press Start (⌘R)", systemImage: "info.circle")
                    .foregroundStyle(DesignToken.Status.neutral)
            }
        }
        .font(DesignToken.Typography.status)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignToken.Spacing.inset)
        .background(DesignToken.Surface.subtle, in: RoundedRectangle(cornerRadius: DesignToken.Radius.status))
        .accessibilityIdentifier(SetupSection.connectionHealth.rawValue)
    }
}

// MARK: - Settings card

struct SettingsCard<Content: View>: View {
    var title: String?
    var accessibilityID: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.field) {
            if let title {
                Text(title)
                    .font(DesignToken.Typography.section)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(SettingsCardContract.heading)
            }
            content()
        }
        .padding(DesignToken.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignToken.Surface.subtle,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.card, style: .continuous)
        )
        .modifier(SettingsCardAccessibility(title: title, accessibilityID: accessibilityID))
        #if DEBUG
        .environment(\.settingsCardIdentity, accessibilityID ?? title)
        #endif
    }
}

/// Heading and group contract applied by `SettingsCard`.
/// The synchronous AppKit accessibility tree does not expose SwiftUI heading traits.
enum SettingsCardContract {
    static let headingLevel = 2
    /// Child controls stay separate elements inside the card group.
    static let containsChildControls = true

    struct Semantics: Equatable {
        var title: String
        var headingLevel: Int
        var containsChildControls: Bool
        var groupLabel: String
    }

    static func semantics(title: String) -> Semantics {
        Semantics(
            title: title,
            headingLevel: headingLevel,
            containsChildControls: containsChildControls,
            groupLabel: title
        )
    }

    static var heading: AccessibilityHeadingLevel {
        switch headingLevel {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        case 6: .h6
        default: .unspecified
        }
    }
}

/// Groups a titled card without combining its controls into one element.
private struct SettingsCardAccessibility: ViewModifier {
    var title: String?
    var accessibilityID: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (title, accessibilityID) {
        case let (title?, id?) where SettingsCardContract.containsChildControls:
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(SettingsCardContract.semantics(title: title).groupLabel)
                .accessibilityIdentifier(id)
        case let (title?, nil) where SettingsCardContract.containsChildControls:
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(SettingsCardContract.semantics(title: title).groupLabel)
        case let (nil, id?):
            content.accessibilityIdentifier(id)
        case (nil, nil):
            content
        default:
            content
        }
    }
}

// MARK: - Endpoint editor

struct EndpointEditorView: View {
    @Bindable var nmeaManager: NMEASimulator
    @Binding var endpoint: OutputEndpoint
    let isPrimary: Bool

    var body: some View {
        let status = nmeaManager.transportStatus(for: endpoint.id)

        VStack(alignment: .leading, spacing: DesignToken.Spacing.field) {
            HStack(spacing: DesignToken.Spacing.header) {
                Text(endpoint.name.isEmpty ? (isPrimary ? "Primary Output" : "Untitled") : endpoint.name)
                    .font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $endpoint.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                if !isPrimary {
                    Button(role: .destructive) {
                        nmeaManager.removeOutputEndpoint(id: endpoint.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove output")
                    .accessibilityLabel("Remove \(endpoint.name.isEmpty ? "output" : endpoint.name)")
                }
            }

            if !endpoint.isEnabled {
                Label("Disabled — not sending", systemImage: "pause.circle")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
            } else if let status {
                Label(status.message, systemImage: status.level.systemImage)
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(status.level.color)
            } else {
                Label("No transport activity yet", systemImage: "questionmark.circle")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
            }

            fieldRow("Name") {
                TextField("Output Name", text: $endpoint.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .accessibilityLabel("Output name")
            }

            fieldRow("Transport") {
                Picker("Transport", selection: $endpoint.transport) {
                    ForEach(NetworkTransport.allCases) { transport in
                        Text(transport.rawValue.uppercased()).tag(transport)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Transport protocol")
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .onChange(of: endpoint.transport) { _, newTransport in
                    if newTransport == .tcp { endpoint.isBroadcast = false }
                }
            }

            if endpoint.transport == .udp {
                Toggle("Broadcast to subnet", isOn: $endpoint.isBroadcast)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
            }

            fieldRow("Host") {
                TextField("Host", text: Binding(
                    get: { endpoint.effectiveHost },
                    set: { if !endpoint.isBroadcast { endpoint.host = $0 } }
                ))
                .disabled(endpoint.transport == .udp && endpoint.isBroadcast)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .accessibilityLabel("Host address")
            }

            fieldRow("Port") {
                DeferredNumericField(port: $endpoint.port, width: 120)
                    .accessibilityLabel("Port number")
            }

            if isPrimary {
                fieldRow("Talker ID") {
                    TextField("Talker ID", text: $nmeaManager.talkerID)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                        .disabled(nmeaManager.selectedProfile != .custom)
                        .accessibilityLabel("Talker ID")
                }

                Text("3 characters, e.g. II or GP. Per-sentence talkers follow the hardware profile unless Custom.")
                    .font(DesignToken.Typography.help)
                    .foregroundStyle(DesignToken.Status.neutral)
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.card) {
            Text(title)
                .font(DesignToken.Typography.field)
                .foregroundStyle(DesignToken.Status.neutral)
                .frame(width: 100, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
