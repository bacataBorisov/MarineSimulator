import SwiftUI

struct MainWindowToolbar: ToolbarContent {
    var nmeaManager: NMEASimulator
    var sidebarNavigation: SidebarNavigation
    @Binding var selectedPanelRawValue: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            DashboardToolbarPanelGroup(sidebarNavigation: sidebarNavigation)
        }

        ToolbarItem(placement: .principal) {
            MiddleStatusToolbarBar(
                nmeaManager: nmeaManager,
                openConnection: {
                    navigateFromToolbar(to: .connection)
                },
                openBoat: {
                    navigateFromToolbar(to: .boat)
                }
            )
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .primaryAction) {
            TransmissionModeBadge(nmeaManager: nmeaManager)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            TransmissionToolbarButton(nmeaManager: nmeaManager)
        }
    }

    private func navigateFromToolbar(to item: SidebarItem) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if sidebarNavigation.selectedItem != item {
                sidebarNavigation.selectedItem = item
            }
            if selectedPanelRawValue != item.rawValue {
                selectedPanelRawValue = item.rawValue
            }
        }
    }
}

private struct DashboardToolbarPanelGroup: View {
    var sidebarNavigation: SidebarNavigation

    @AppStorage("dashboard.show_left_dock") private var showLeftDock = true
    @AppStorage("dashboard.show_right_inspector") private var showRightInspector = true
    @AppStorage(ConsoleHeightStorage.key) private var storedLogHeight: Double = 220
    @AppStorage("console_panel.last_expanded_height") private var lastExpandedConsoleHeight: Double = 220

    private var showConsoleBinding: Binding<Bool> {
        Binding(
            get: { storedLogHeight > 0 },
            set: { expanded in
                if expanded {
                    storedLogHeight = max(lastExpandedConsoleHeight, 140)
                } else {
                    if storedLogHeight > 0 {
                        lastExpandedConsoleHeight = max(storedLogHeight, 140)
                    }
                    storedLogHeight = 0
                }
            }
        )
    }

    var body: some View {
        let isDashboard = sidebarNavigation.selectedItem == .dashboard
        HStack(spacing: 6) {
            DashboardPanelToggleButton(
                title: "Controls",
                systemImage: "slider.horizontal.below.rectangle",
                isOn: $showLeftDock
            )
            DashboardPanelToggleButton(
                title: "Instruments",
                systemImage: "gauge.with.needle",
                isOn: $showRightInspector
            )
            DashboardPanelToggleButton(
                title: "Console Log",
                systemImage: "terminal",
                isOn: showConsoleBinding
            )
        }
        .opacity(isDashboard ? 1 : 0)
        .disabled(!isDashboard)
        .accessibilityHidden(!isDashboard)
    }
}

private struct MiddleStatusToolbarBar: View {
    @Bindable var nmeaManager: NMEASimulator
    var openConnection: () -> Void
    var openBoat: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            statusCluster(compact: false)
            statusCluster(compact: true)
        }
    }

    private func statusCluster(compact: Bool) -> some View {
        HStack(spacing: DesignToken.Spacing.row) {
            ConnectionStatusPill(nmeaManager: nmeaManager, compact: compact, action: openConnection)
            WeatherModeToolbarPill(nmeaManager: nmeaManager, compact: compact)
            ActiveVesselToolbarPill(nmeaManager: nmeaManager, compact: compact, action: openBoat)
        }
    }
}

private struct ConnectionStatusPill: View {
    @Bindable var nmeaManager: NMEASimulator
    var compact: Bool
    var action: () -> Void

    var body: some View {
        let activity = nmeaManager.isTransmitting ? "Transmitting" : "Idle"
        let fullDetail = [activity, nmeaManager.latestTransportStatus?.message, PrimaryOutputSummary.label(for: nmeaManager)]
            .compactMap { $0 }
            .joined(separator: " · ")
        let displayText = compact ? activity : fullDetail
        let systemImage = nmeaManager.isTransmitting
            ? "antenna.radiowaves.left.and.right"
            : "antenna.radiowaves.left.and.right.slash"
        let tint = nmeaManager.isTransmitting ? DesignToken.Status.success : DesignToken.Status.neutral

        Button(action: action) {
            Label(displayText, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, DesignToken.Spacing.inset)
                .padding(.vertical, DesignToken.Spacing.stacked)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(fullDetail)
        .accessibilityLabel(fullDetail)
    }
}

private struct WeatherModeToolbarPill: View {
    @Bindable var nmeaManager: NMEASimulator
    var compact: Bool
    @State private var showIssuePopover = false

    var body: some View {
        let isLive = nmeaManager.weatherSourceMode == .liveWeather
        let gpsMissing = isLive && !nmeaManager.sensorToggles.hasGPS
        let hasFailure = isLive && nmeaManager.liveWeatherStatus.state == .failed
        let title: String = {
            if !isLive { return "Manual" }
            if gpsMissing { return compact ? "GPS Off" : "Live Weather · Enable GPS" }
            switch nmeaManager.liveWeatherStatus.state {
            case .fetching: return compact ? "Live" : "Fetching…"
            case .failed: return compact ? "Live!" : "Weather Error"
            case .ready: return "Live Weather"
            case .idle: return "Live Weather"
            }
        }()
        let systemImage: String = {
            if !isLive { return "slider.horizontal.3" }
            if gpsMissing { return "location.slash" }
            switch nmeaManager.liveWeatherStatus.state {
            case .idle: return "cloud.sun.fill"
            case .fetching: return "arrow.triangle.2.circlepath"
            case .ready: return "checkmark.circle.fill"
            case .failed: return "exclamationmark.triangle.fill"
            }
        }()
        let tint: Color = {
            if !isLive { return DesignToken.Status.neutral }
            if gpsMissing { return DesignToken.Status.warning }
            switch nmeaManager.liveWeatherStatus.state {
            case .idle: return DesignToken.Status.info
            case .fetching: return DesignToken.Status.warning
            case .ready: return DesignToken.Status.success
            case .failed: return DesignToken.Status.error
            }
        }()
        let helpText: String = {
            if !isLive {
                return "Manual weather controls active. Click to switch to Live Weather."
            }
            if gpsMissing {
                return "GPS is disabled in Simulation, so live weather cannot determine the boat's position."
            }
            let provider = nmeaManager.latestLiveWeather?.sourceName
            let details = [provider, nmeaManager.liveWeatherStatus.message].compactMap { $0 }.joined(separator: " — ")
            return "\(details). Click to switch to Manual weather."
        }()

        Button {
            if gpsMissing || hasFailure {
                showIssuePopover = true
            } else {
                nmeaManager.weatherSourceMode = isLive ? .manual : .liveWeather
            }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, DesignToken.Spacing.inset)
                .padding(.vertical, DesignToken.Spacing.stacked)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .popover(isPresented: $showIssuePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.header) {
                Text(gpsMissing ? "GPS Required for Live Weather" : "Live Weather Unavailable")
                    .font(.headline)

                Text(
                    gpsMissing
                        ? "GPS is disabled in Simulation, so live weather cannot determine the boat's position."
                        : nmeaManager.liveWeatherStatus.message
                )
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DesignToken.Spacing.row) {
                    if gpsMissing {
                        Button("Enable GPS") {
                            showIssuePopover = false
                            nmeaManager.sensorToggles.hasGPS = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Retry Fetch") {
                            showIssuePopover = false
                            nmeaManager.refreshLiveWeather(force: true)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Switch to Manual") {
                        showIssuePopover = false
                        nmeaManager.weatherSourceMode = .manual
                    }
                }
            }
            .padding(DesignToken.Spacing.card)
            .frame(width: 280)
        }
    }
}

private struct ActiveVesselToolbarPill: View {
    @Bindable var nmeaManager: NMEASimulator
    var compact: Bool
    var action: () -> Void

    var body: some View {
        let name = nmeaManager.activeVesselName
        Button(action: action) {
            Group {
                if compact {
                    Label(name, systemImage: "sailboat")
                        .labelStyle(.iconOnly)
                } else {
                    Label(name, systemImage: "sailboat")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(DesignToken.Typography.supporting)
            .foregroundStyle(nmeaManager.vesselAllowsSimulation ? .primary : DesignToken.Status.warning)
            .lineLimit(1)
            .padding(.horizontal, DesignToken.Spacing.inset)
            .padding(.vertical, DesignToken.Spacing.stacked)
            .background(DesignToken.Status.neutral.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Active boat: \(name). Click to open Boat Profile.")
        .accessibilityLabel("Active boat \(name)")
    }
}

private struct DashboardPanelToggleButton: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(isOn ? DesignToken.accentPrimary : DesignToken.Status.neutral)
        }
        .help("\(isOn ? "Hide" : "Show") \(title)")
        .accessibilityLabel("\(title) \(isOn ? "shown" : "hidden")")
    }
}

private struct TransmissionModeBadge: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        let isBurst = !nmeaManager.isTimerSelected
        Text(isBurst ? "Burst" : "Continuous")
            .font(DesignToken.Typography.supporting)
            .foregroundStyle(isBurst ? DesignToken.Status.warning : DesignToken.Status.neutral)
            .padding(.horizontal, DesignToken.Spacing.row)
            .padding(.vertical, DesignToken.Spacing.stacked)
            .background(
                (isBurst ? DesignToken.Status.warning : DesignToken.Status.neutral).opacity(0.14),
                in: Capsule()
            )
    }
}

private struct TransmissionToolbarButton: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        let buttonTitle = nmeaManager.isTransmitting ? "Stop" : "Start"
        let systemImage = nmeaManager.isTransmitting
            ? "stop.fill"
            : (nmeaManager.isTimerSelected ? "play.fill" : "play.circle")
        Button {
            if nmeaManager.isTransmitting {
                nmeaManager.stopSimulation()
            } else {
                nmeaManager.startSimulation()
            }
        } label: {
            Label(buttonTitle, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .help(
            nmeaManager.isTransmitting
                ? "Stop sending data (⌘R)"
                : (nmeaManager.isTimerSelected
                    ? "Start continuous sending (⌘R)"
                    : "Send single burst — Enable Timer is off in Connection (⌘R)")
        )
        .keyboardShortcut("r", modifiers: .command)
    }
}
