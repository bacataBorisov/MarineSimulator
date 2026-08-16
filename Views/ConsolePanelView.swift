import SwiftUI
import AppKit
import Combine

struct ConsolePanelView: View {
    static let toolbarHeight: CGFloat = 36

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var nmeaManager: NMEASimulator
    @Binding var consoleHeight: CGFloat
    let geometryHeight: CGFloat

    private let spacing: CGFloat = 8
    private let collapsedContentHeight: CGFloat = 0
    private let expandedMinimumHeight: CGFloat = 140
    private let parkThreshold: CGFloat = 8

    @AppStorage("console_panel.mode") private var consoleModeRawValue: String = ConsoleView.Mode.nmea.rawValue
    @AppStorage("console_panel.last_expanded_height") private var lastExpandedHeight: Double = 220
    @State private var animatedHeight: CGFloat = 0
    @State private var liveHeight: CGFloat?
    @State private var dragOrigin: CGFloat?
    @State private var dragMaxHeight: CGFloat?
    @State private var statsRefreshDate = Date()

    private let statsTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var isCollapsed: Bool { displayedHeight <= collapsedContentHeight }

    private var displayedHeight: CGFloat {
        liveHeight ?? animatedHeight
    }

    private var toggleAnimation: Animation {
        .snappy(duration: 0.32, extraBounce: 0)
    }

    private var resolvedMode: ConsoleView.Mode {
        ConsoleView.Mode(rawValue: consoleModeRawValue) ?? .nmea
    }

    private var consoleMode: Binding<ConsoleView.Mode> {
        Binding(
            get: { ConsoleView.Mode(rawValue: consoleModeRawValue) ?? .nmea },
            set: { consoleModeRawValue = $0.rawValue }
        )
    }

    private var maxLogHeight: CGFloat {
        max(
            expandedMinimumHeight,
            geometryHeight - UIConstants.tabBarHeight - Self.toolbarHeight - 80
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ConsoleView(mode: resolvedMode, isActive: displayedHeight > 1)
                .frame(height: displayedHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .allowsHitTesting(displayedHeight > 1)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            if liveHeight != nil {
                transaction.animation = nil
            }
        }
        .onAppear {
            animatedHeight = consoleHeight
            if consoleHeight > parkThreshold {
                lastExpandedHeight = Double(max(consoleHeight, expandedMinimumHeight))
            }
        }
        .onChange(of: consoleHeight) { _, newValue in
            guard liveHeight == nil, abs(animatedHeight - newValue) > 0.5 else { return }
            setAnimatedHeight(newValue, animated: !reduceMotion)
        }
        .onReceive(statsTimer) { date in
            statsRefreshDate = date
        }
    }

    private var toolbar: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            AppColors.consoleChrome.opacity(0.45)

            // Window-space drag: SwiftUI DragGesture is in the moving bar's
            // coordinates and fights the parent split every frame.
            ConsoleResizeHandle(
                onBegan: beginResize,
                onDragged: updateResize,
                onEnded: endResize
            )

            HStack(spacing: 10) {
                Button {
                    toggleCollapsedState()
                } label: {
                    Image(systemName: isCollapsed ? "rectangle.bottomhalf.inset.filled" : "rectangle.bottomhalf.filled")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(isCollapsed ? "Show Console" : "Hide Console")

                Picker("Console Mode", selection: consoleMode) {
                    ForEach(ConsoleView.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 188)
                .controlSize(.small)

                if resolvedMode == .nmea {
                    let _ = statsRefreshDate
                    toolbarMetric("Rate", "\(nmeaManager.sentPerSecond())/s")
                        .help("Sentences transmitted in the last second")
                    toolbarMetric("Total", "\(nmeaManager.totalSentCount)")
                        .help("Total sentences sent this session")
                    toolbarMetric("Tick", formattedSimulatorInterval)
                        .help("Base send-interval from Connection → Transmission")
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                Button {
                    let text: String
                    if resolvedMode == .nmea {
                        text = nmeaManager.nmeaConsoleExportText()
                    } else {
                        text = nmeaManager.transportHistoryExportText()
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(resolvedMode == .nmea ? "Copy NMEA console" : "Copy transport history")
                .disabled(
                    resolvedMode == .nmea
                    ? nmeaManager.allOutputMessageRecords.isEmpty
                    : nmeaManager.transportHistory.isEmpty
                )

                Button {
                    if resolvedMode == .nmea {
                        nmeaManager.clearOutputMessages()
                    } else {
                        nmeaManager.clearTransportHistory()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Clear console")
            }
            .padding(.horizontal, spacing)
        }
        .frame(height: Self.toolbarHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            ConsoleResizeHandle(
                onBegan: beginResize,
                onDragged: updateResize,
                onEnded: endResize
            )
            .frame(height: 10)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private func beginResize() {
        dragOrigin = displayedHeight
        dragMaxHeight = maxLogHeight
    }

    private func updateResize(windowDeltaY: CGFloat) {
        let origin = dragOrigin ?? displayedHeight
        let next = min(max(origin + windowDeltaY, collapsedContentHeight), dragMaxHeight ?? maxLogHeight)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            liveHeight = next
        }
    }

    private func endResize() {
        let finalHeight = liveHeight ?? consoleHeight
        let parked = finalHeight < parkThreshold ? collapsedContentHeight : finalHeight
        if parked > parkThreshold {
            lastExpandedHeight = Double(parked)
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            animatedHeight = parked
            consoleHeight = parked
            liveHeight = nil
            dragOrigin = nil
            dragMaxHeight = nil
        }
    }

    private func toolbarMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    private var formattedSimulatorInterval: String {
        if nmeaManager.interval >= 1.0 {
            return String(format: "%.1f s", nmeaManager.interval)
        }
        return String(format: "%.0f ms", nmeaManager.interval * 1000)
    }

    private func toggleCollapsedState() {
        let target: CGFloat
        if isCollapsed {
            target = max(CGFloat(lastExpandedHeight), expandedMinimumHeight)
        } else {
            lastExpandedHeight = Double(max(displayedHeight, expandedMinimumHeight))
            target = collapsedContentHeight
        }
        consoleHeight = target
        setAnimatedHeight(target, animated: !reduceMotion)
    }

    private func setAnimatedHeight(_ height: CGFloat, animated: Bool) {
        if animated {
            withAnimation(toggleAnimation) {
                animatedHeight = height
            }
        } else {
            animatedHeight = height
        }
    }
}

/// Window-space resize handle. SwiftUI `DragGesture` uses the moving bar's
/// local coordinates, which fights the parent split and jitters.
private struct ConsoleResizeHandle: NSViewRepresentable {
    var onBegan: () -> Void
    var onDragged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> ConsoleResizeHandleView {
        let view = ConsoleResizeHandleView()
        view.onBegan = onBegan
        view.onDragged = onDragged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: ConsoleResizeHandleView, context: Context) {
        view.onBegan = onBegan
        view.onDragged = onDragged
        view.onEnded = onEnded
    }
}

private final class ConsoleResizeHandleView: NSView {
    var onBegan: (() -> Void)?
    var onDragged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?
    private var startY: CGFloat?

    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        startY = event.locationInWindow.y
        onBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startY else { return }
        onDragged?(event.locationInWindow.y - startY)
    }

    override func mouseUp(with event: NSEvent) {
        onEnded?()
        startY = nil
    }
}
