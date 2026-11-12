import SwiftUI
import AppKit

/// One scroll sample used to decide whether a console drag should move the page.
struct ConsoleViewport: Equatable {
    var offsetY: CGFloat
    var viewportHeight: CGFloat
    var contentHeight: CGFloat
}

/// Shared drag flag. The console handle sets it. Scroll anchors read it. It is not a second height.
final class ConsoleDragTracking {
    var isDragging = false
}

private struct ConsoleDragTrackingKey: EnvironmentKey {
    static let defaultValue = ConsoleDragTracking()
}

extension EnvironmentValues {
    var consoleDragTracking: ConsoleDragTracking {
        get { self[ConsoleDragTrackingKey.self] }
        set { self[ConsoleDragTrackingKey.self] = newValue }
    }
}

/// Session-owned presentation memory. `MainView` holds the instance the window uses.
/// Offsets are document points for one sidebar page and one scroll slot. They are not simulator state.
final class PagePresentationSession {
    private var offsets: [PageScrollKey: CGFloat] = [:]
    var manualSearch = ""
    var manualTopicID: UUID?

    func storedOffset(page: SidebarItem, slot: String) -> CGFloat? {
        offsets[PageScrollKey(page: page, slot: slot)]
    }

    func remember(_ offset: CGFloat, page: SidebarItem, slot: String) {
        offsets[PageScrollKey(page: page, slot: slot)] = offset
    }
}

struct PageScrollKey: Hashable {
    var page: SidebarItem
    var slot: String
}

/// The clip view's legal origin range for one viewport height.
/// `constrainBoundsRect` includes content insets, so the minimum can be negative.
/// An origin past that minimum is rubber-band overscroll, not a document point `scroll(to:)` should keep.
struct ConsoleScrollLimits: Equatable {
    var minimum: CGFloat
    var maximum: CGFloat

    func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }

    static func reading(_ clip: NSClipView, viewportHeight: CGFloat) -> ConsoleScrollLimits {
        var proposed = clip.bounds
        proposed.size.height = viewportHeight
        proposed.origin.y = -1_000_000_000
        let minimum = clip.constrainBoundsRect(proposed).origin.y
        proposed.origin.y = 1_000_000_000
        let maximum = clip.constrainBoundsRect(proposed).origin.y
        return ConsoleScrollLimits(minimum: minimum, maximum: maximum)
    }

    /// Limits for a sample that may be older than the clip view's current document.
    /// A content-height change is already applied when the callback runs, so the pin is judged against the sample's own document.
    static func reading(_ clip: NSClipView, matching sample: ConsoleViewport) -> ConsoleScrollLimits {
        let live = reading(clip, viewportHeight: sample.viewportHeight)
        let liveContent = clip.documentView?.bounds.height ?? sample.contentHeight
        guard abs(liveContent - sample.contentHeight) > 0.5 else { return live }
        let bias = live.maximum - (liveContent - sample.viewportHeight)
        return ConsoleScrollLimits(
            minimum: live.minimum,
            maximum: max(live.minimum, sample.contentHeight - sample.viewportHeight + bias)
        )
    }
}

/// Clamps a stored document offset into the scroll view that exists now.
enum PageScrollRestoration {
    static func clampedOffset(_ stored: CGFloat, limits: ConsoleScrollLimits) -> CGFloat {
        limits.clamped(stored)
    }
}

private struct PagePresentationKey: EnvironmentKey {
    static let defaultValue = PagePresentationSession()
}

private struct PageScrollIdentityKey: EnvironmentKey {
    static let defaultValue: SidebarItem? = nil
}

extension EnvironmentValues {
    var pagePresentation: PagePresentationSession {
        get { self[PagePresentationKey.self] }
        set { self[PagePresentationKey.self] = newValue }
    }

    /// The sidebar destination whose scroll slots this subtree records. Nil outside a shell page.
    var pageScrollIdentity: SidebarItem? {
        get { self[PageScrollIdentityKey.self] }
        set { self[PageScrollIdentityKey.self] = newValue }
    }
}

/// The scroll view's position when the console handle went down. It is not the stored page offset.
/// `offsetY` is inside the clip view's constrained range. Rubber-band overscroll is not part of it.
struct ConsoleDragBaseline {
    var offsetY: CGFloat
    var viewportHeight: CGFloat
    var contentHeight: CGFloat
    var pinnedToBottom: Bool
}

/// Keeps the document point at the console edge during a console drag.
enum ConsoleScrollTracking {
    /// The offset for this viewport, measured from the gesture baseline rather than the previous sample.
    /// The result stays inside `limits`, including a negative inset minimum.
    static func offsetDuringDrag(
        baseline: ConsoleDragBaseline,
        viewport: ConsoleViewport,
        limits: ConsoleScrollLimits
    ) -> CGFloat {
        if baseline.pinnedToBottom {
            return limits.maximum
        }
        let delta = baseline.viewportHeight - viewport.viewportHeight
        return limits.clamped(baseline.offsetY + delta)
    }

    static func baseline(from sample: ConsoleViewport, limits: ConsoleScrollLimits) -> ConsoleDragBaseline {
        let span = limits.maximum - limits.minimum
        let legal = limits.clamped(sample.offsetY)
        return ConsoleDragBaseline(
            offsetY: legal,
            viewportHeight: sample.viewportHeight,
            contentHeight: sample.contentHeight,
            pinnedToBottom: span > 1 && abs(legal - limits.maximum) <= 1
        )
    }
}

/// Places an anchor inside the scrolling content. The anchor’s enclosing scroll view is the one that moves.
private struct ConsoleEdgeScrollTracking: ViewModifier {
    var isEnabled: Bool
    var slot: String
    @Environment(\.consoleDragTracking) private var dragTracking
    @Environment(\.pagePresentation) private var presentation
    @Environment(\.pageScrollIdentity) private var page

    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay(alignment: .topLeading) {
                ConsoleEdgeScrollBridge(
                    dragTracking: dragTracking,
                    presentation: presentation,
                    page: page,
                    slot: slot
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

/// Writes the page clip view. `ScrollPosition` did not move this scroller, so restoration uses the same clip view.
private struct ConsoleEdgeScrollBridge: NSViewRepresentable {
    var dragTracking: ConsoleDragTracking
    var presentation: PagePresentationSession
    var page: SidebarItem?
    var slot: String

    func makeNSView(context: Context) -> ConsoleEdgeAnchorView {
        ConsoleEdgeAnchorView(
            dragTracking: dragTracking,
            presentation: presentation,
            page: page,
            slot: slot
        )
    }

    func updateNSView(_ view: ConsoleEdgeAnchorView, context: Context) {
        view.dragTracking = dragTracking
        view.presentation = presentation
        view.noteEnvironmentIdentity(page: page, slot: slot)
    }

    static func dismantleNSView(_ nsView: ConsoleEdgeAnchorView, coordinator: ()) {
        nsView.captureForDeparture()
    }
}

/// Lives inside one page scroller and adjusts that scroller’s clip view.
final class ConsoleEdgeAnchorView: NSView {
    var dragTracking: ConsoleDragTracking
    var presentation: PagePresentationSession?
    private var page: SidebarItem?
    private var slot: String
    private var boundPage: SidebarItem?
    private var boundSlot: String?
    private weak var scrollView: NSScrollView?
    private var previous: ConsoleViewport?
    private var dragBaseline: ConsoleDragBaseline?
    private var originBeforeApply: CGFloat?
    private var isApplying = false
    /// The last origin this anchor wrote, with the viewport height it belonged to.
    /// `didLiveScrollNotification` echoes that same pair when AppKit posts it for the write; a user scroll does not.
    private var lastProgrammaticOrigin: CGFloat?
    private var lastProgrammaticViewport: CGFloat?
    /// The origin a drag write just replaced, and the viewport height it belonged to.
    /// The bounds mutation can publish that same origin once more after `scroll(to:)` returns.
    private var echoViewport: CGFloat?
    private var echoOrigin: CGFloat?
    private var didRestore = false
    private var isDetaching = false
    private var retired = false
    private var committedOffset: CGFloat?
    #if DEBUG
    var scrollTrace = ScrollRuntimeTrace.shared
    private var lastTraceKey = ""
    private var lastRequested: CGFloat?
    #endif

    init(
        dragTracking: ConsoleDragTracking,
        presentation: PagePresentationSession? = nil,
        page: SidebarItem? = nil,
        slot: String = "primary"
    ) {
        self.dragTracking = dragTracking
        self.presentation = presentation
        self.page = page
        self.slot = slot
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        #if DEBUG
        trace("anchorCreated", note: "page=\(page?.rawValue ?? "-") slot=\(slot)", force: true)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            isDetaching = true
            if let committedOffset,
               let clip = scrollView?.contentView,
               clip.bounds.origin.y < 0.5,
               committedOffset > 1 {
                remember(committedOffset)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        bindIfNeeded()
    }

    override func layout() {
        super.layout()
        bindIfNeeded()
        followViewport()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func bindIfNeeded() {
        guard scrollView == nil, let found = enclosingScrollView else { return }
        scrollView = found
        found.contentView.postsBoundsChangedNotifications = true
        found.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: found.contentView)
        center.addObserver(self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: found)
        center.addObserver(self, selector: #selector(userDidLiveScroll), name: NSScrollView.didLiveScrollNotification, object: found)
        #if DEBUG
        scrollTrace.bindAnchor(
            self,
            scrollView: found,
            clipView: found.contentView,
            label: "\((boundPage ?? page)?.rawValue ?? "-")/\(boundSlot ?? slot)"
        )
        trace(
            "anchorBound",
            note: "document=\(ScrollRuntimeTrace.identity(found.documentView))",
            force: true
        )
        #endif
    }

    @objc private func viewportChanged() {
        followViewport()
    }

    /// Posted after a user event changes the clip origin. Legacy scroll wheels post this without a
    /// `willStart`/`didEnd` pair. Those session notifications also stay active for a whole trackpad
    /// gesture, so a layout callback in between must not use them.
    @objc private func userDidLiveScroll(_ notification: Notification) {
        guard dragTracking.isDragging, !isApplying, !retired, !isDetaching else { return }
        guard let scrollView, (notification.object as AnyObject?) === scrollView else { return }
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let raw = ConsoleViewport(
            offsetY: clip.bounds.origin.y,
            viewportHeight: clip.bounds.height,
            contentHeight: document.bounds.height
        )
        guard raw.contentHeight > 1, raw.viewportHeight > 1 else { return }
        if let lastProgrammaticOrigin, let lastProgrammaticViewport,
           abs(raw.offsetY - lastProgrammaticOrigin) <= 0.5,
           abs(raw.viewportHeight - lastProgrammaticViewport) <= 0.5 {
            return
        }
        freezeIdentityIfNeeded()
        let limits = ConsoleScrollLimits.reading(clip, matching: raw)
        let legal = limits.clamped(raw.offsetY)
        let sample = ConsoleViewport(
            offsetY: legal,
            viewportHeight: raw.viewportHeight,
            contentHeight: raw.contentHeight
        )
        dragBaseline = ConsoleScrollTracking.baseline(from: sample, limits: limits)
        previous = sample
        echoViewport = nil
        echoOrigin = nil
        lastProgrammaticOrigin = nil
        lastProgrammaticViewport = nil
        remember(legal, note: "baseline replaced")
        #if DEBUG
        trace(
            "baselineReplaced",
            clip: clip,
            documentHeight: raw.contentHeight,
            viewportHeight: raw.viewportHeight,
            origin: legal,
            note: abs(raw.offsetY - legal) > 0.5
                ? "didLiveScroll clamped rubber-band overscroll"
                : "didLiveScroll",
            force: true
        )
        #endif
    }

    /// Freezes the region on the first real sample. A later environment change cannot retarget this scroll view.
    func noteEnvironmentIdentity(page: SidebarItem?, slot: String) {
        guard !retired else { return }
        if let boundPage {
            if boundPage != page || boundSlot != slot {
                captureForDeparture()
                retired = true
            }
            return
        }
        self.page = page
        self.slot = slot
    }

    func followViewport() {
        guard !isApplying else { return }
        if isDetaching || retired {
            #if DEBUG
            trace("lateCallback", note: retired ? "retired" : "detaching")
            #endif
            return
        }
        guard let scrollView, let document = scrollView.documentView else { return }
        #if DEBUG
        if let found = enclosingScrollView, found !== scrollView {
            trace(
                "enclosingMismatch",
                note: "bound=\(ScrollRuntimeTrace.identity(scrollView)) enclosing=\(ScrollRuntimeTrace.identity(found))"
            )
        }
        #endif
        freezeIdentityIfNeeded()
        let clip = scrollView.contentView
        let next = ConsoleViewport(
            offsetY: clip.bounds.origin.y,
            viewportHeight: clip.bounds.height,
            contentHeight: document.bounds.height
        )
        guard next.contentHeight > 1, next.viewportHeight > 1 else { return }
        if presentation != nil && boundPage == nil {
            #if DEBUG
            trace("waitingForIdentity", note: "environment=\(page?.rawValue ?? "-")/\(slot)")
            #endif
            return
        }

        if !didRestore {
            didRestore = true
            if let boundPage, let boundSlot, let presentation,
               let stored = presentation.storedOffset(page: boundPage, slot: boundSlot) {
                let target = PageScrollRestoration.clampedOffset(
                    stored,
                    limits: ConsoleScrollLimits.reading(clip, viewportHeight: next.viewportHeight)
                )
                if abs(target - next.offsetY) > 0.5 {
                    apply(target, to: clip)
                }
                previous = snapshot(clip.bounds.origin.y, next)
                #if DEBUG
                trace(
                    "offsetRestored",
                    clip: clip,
                    documentHeight: next.contentHeight,
                    viewportHeight: next.viewportHeight,
                    origin: clip.bounds.origin.y,
                    requested: target,
                    observed: clip.bounds.origin.y,
                    note: "stored=\(stored)",
                    force: true
                )
                #endif
                return
            }
            previous = next
            remember(next.offsetY)
            return
        }

        guard let previous else {
            self.previous = next
            return
        }

        #if DEBUG
        if let lastRequested,
           abs(next.offsetY - lastRequested) > 0.5,
           abs(next.offsetY - previous.offsetY) > 0.5 {
            trace(
                "boundsAfterWrite",
                clip: clip,
                documentHeight: next.contentHeight,
                viewportHeight: next.viewportHeight,
                origin: next.offsetY,
                requested: lastRequested,
                observed: next.offsetY,
                note: "incoming origin differs from the last programmatic write",
                force: true
            )
        }
        #endif

        if dragTracking.isDragging {
            followDrag(from: previous, to: next, clip: clip)
            return
        }
        echoViewport = nil
        echoOrigin = nil
        dragBaseline = nil

        let originChanged = abs(next.offsetY - previous.offsetY) > 0.5
        let viewportChanged = abs(next.viewportHeight - previous.viewportHeight) > 0.5
        let contentChanged = abs(next.contentHeight - previous.contentHeight) > 0.5
        let jumpedHome = next.offsetY < 0.5 && previous.offsetY > 1
        if jumpedHome && window == nil { return }
        self.previous = next
        if originChanged {
            remember(next.offsetY, note: "user")
            #if DEBUG
            trace(
                "userScroll",
                clip: clip,
                documentHeight: next.contentHeight,
                viewportHeight: next.viewportHeight,
                origin: next.offsetY,
                note: "origin changed while the console handle was up",
                force: true
            )
            #endif
        } else if viewportChanged || contentChanged {
            #if DEBUG
            trace(
                "clipChanged",
                clip: clip,
                documentHeight: next.contentHeight,
                viewportHeight: next.viewportHeight,
                origin: next.offsetY,
                note: "layout"
            )
            #endif
        }
    }

    private func followDrag(from previous: ConsoleViewport, to next: ConsoleViewport, clip: NSClipView) {
        if dragBaseline == nil {
            let startLimits = ConsoleScrollLimits.reading(clip, matching: previous)
            dragBaseline = ConsoleScrollTracking.baseline(from: previous, limits: startLimits)
            #if DEBUG
            trace(
                "dragBaseline",
                documentHeight: previous.contentHeight,
                viewportHeight: previous.viewportHeight,
                origin: previous.offsetY,
                note: "captured when the handle was already down",
                force: true
            )
            #endif
        }
        guard let baseline = dragBaseline else { return }
        let viewportStable = abs(next.viewportHeight - previous.viewportHeight) <= 0.5
        let contentStable = abs(next.contentHeight - previous.contentHeight) <= 0.5
        let limits = ConsoleScrollLimits.reading(clip, viewportHeight: next.viewportHeight)
        let proposed = ConsoleScrollTracking.offsetDuringDrag(baseline: baseline, viewport: next, limits: limits)
        let correctingEcho = viewportStable && contentStable
        if correctingEcho {
            let echoHeight = echoViewport
            let echoOrigin = self.echoOrigin
            echoViewport = nil
            self.echoOrigin = nil
            let heightMatches = echoHeight.map { abs($0 - next.viewportHeight) <= 0.5 } ?? false
            let originMatches = echoOrigin.map { abs($0 - next.offsetY) <= 0.5 } ?? false
            let echoMatches = heightMatches && originMatches
            guard abs(next.offsetY - proposed) > 0.5, echoMatches else {
                // The origin moved before the viewport height for this console step was published.
                // The target depends on that height, so this callback does not write. A user scroll
                // is `didLiveScrollNotification`, which rebases after the origin has changed.
                return
            }
        } else {
            echoViewport = nil
            echoOrigin = nil
        }
        if abs(proposed - next.offsetY) > 0.5 {
            apply(proposed, to: clip)
            if !correctingEcho, let replaced = originBeforeApply, abs(clip.bounds.origin.y - proposed) <= 0.5 {
                armEcho(viewport: next.viewportHeight, origin: replaced)
            }
        }
        let settled = clip.bounds.origin.y
        self.previous = snapshot(settled, next)
        remember(settled)
    }

    /// The bounds change that provoked a write can publish the replaced origin once more after `scroll(to:)` returns.
    /// The latch expires before the next event, so a later user scroll is not an echo.
    private func armEcho(viewport: CGFloat, origin: CGFloat) {
        echoViewport = viewport
        echoOrigin = origin
        DispatchQueue.main.async { [weak self] in
            guard let self, let armed = self.echoViewport, abs(armed - viewport) <= 0.5 else { return }
            self.echoViewport = nil
            self.echoOrigin = nil
        }
    }

    private func freezeIdentityIfNeeded() {
        guard boundPage == nil, let page else { return }
        boundPage = page
        boundSlot = slot
    }

    private func snapshot(_ offsetY: CGFloat, _ sample: ConsoleViewport) -> ConsoleViewport {
        ConsoleViewport(offsetY: offsetY, viewportHeight: sample.viewportHeight, contentHeight: sample.contentHeight)
    }

    func captureForDeparture() {
        #if DEBUG
        trace("anchorRetired", note: "departure", force: true)
        scrollTrace.unbindAnchor(self)
        #endif
        guard !isDetaching else { return }
        isDetaching = true
        guard let clip = scrollView?.contentView else { return }
        let visible = clip.bounds.origin.y
        if visible > 1 {
            remember(visible)
        } else if let committedOffset, committedOffset > 1 {
            remember(committedOffset)
        } else {
            remember(visible)
        }
    }

    private func apply(_ y: CGFloat, to clip: NSClipView) {
        originBeforeApply = clip.bounds.origin.y
        var origin = clip.bounds.origin
        origin.y = y
        isApplying = true
        clip.scroll(to: origin)
        isApplying = false
        let observed = clip.bounds.origin.y
        lastProgrammaticOrigin = observed
        lastProgrammaticViewport = clip.bounds.height
        #if DEBUG
        lastRequested = y
        trace(
            "programmaticWrite",
            clip: clip,
            origin: observed,
            requested: y,
            observed: observed,
            note: "before=\(originBeforeApply.map { String(format: "%.3f", $0) } ?? "-")",
            force: true
        )
        #endif
    }

    private func remember(_ offset: CGFloat, note: String = "") {
        guard !retired, let boundPage, let boundSlot, let presentation else { return }
        committedOffset = offset
        presentation.remember(offset, page: boundPage, slot: boundSlot)
        #if DEBUG
        trace(
            "offsetSaved",
            origin: offset,
            note: note.isEmpty ? "\(boundPage.rawValue)/\(boundSlot)" : "\(boundPage.rawValue)/\(boundSlot) \(note)",
            force: true
        )
        #endif
    }

    #if DEBUG
    private func trace(
        _ kind: String,
        clip: NSClipView? = nil,
        documentHeight: CGFloat? = nil,
        viewportHeight: CGFloat? = nil,
        origin: CGFloat? = nil,
        requested: CGFloat? = nil,
        observed: CGFloat? = nil,
        note: String = "",
        force: Bool = false
    ) {
        guard scrollTrace.isCapturing else { return }
        let clipView = clip ?? scrollView?.contentView
        let document = scrollView?.documentView
        let doc = documentHeight ?? document?.bounds.height
        let viewHeight = viewportHeight ?? clipView?.bounds.height
        let originY = origin ?? observed ?? clipView?.bounds.origin.y
        let stored = boundPage.flatMap { page in
            boundSlot.flatMap { slot in presentation?.storedOffset(page: page, slot: slot) }
        }
        let key = "\(kind)|\(originY ?? -1)|\(viewHeight ?? -1)|\(doc ?? -1)|\(requested ?? -1)|\(observed ?? -1)|\(note)"
        if !force && key == lastTraceKey { return }
        lastTraceKey = key
        scrollTrace.record(
            kind: kind,
            frozenPage: (boundPage ?? page)?.rawValue ?? "-",
            slot: boundSlot ?? slot,
            anchor: self,
            scrollView: scrollView,
            clipView: clipView,
            documentHeight: doc,
            viewportHeight: viewHeight,
            origin: originY,
            stored: stored,
            dragging: dragTracking.isDragging,
            requested: requested,
            observed: observed,
            note: note
        )
    }
    #endif
}

extension View {
    /// Tracks the shell console from inside this scrolling content, and restores that scroller for its page slot.
    /// Do not use it on the dashboard map.
    /// Pass `false` for every row except one, so a list does not adjust the same drag twice.
    /// `slot` distinguishes nested scrollers on one sidebar page. The page itself comes from the environment.
    func tracksConsoleEdge(_ enabled: Bool = true, slot: String = "primary") -> some View {
        modifier(ConsoleEdgeScrollTracking(isEnabled: enabled, slot: slot))
    }
}

/// Scrollable page shell used by Connection and the other sidebar panels.
struct PageContainer<Content: View>: View {
    var maxWidth: CGFloat = PageChrome.maxWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .pageContentFrame(maxWidth: maxWidth)
                .tracksConsoleEdge()
        }
    }
}

extension View {
    func pageContentFrame(maxWidth: CGFloat = PageChrome.maxWidth) -> some View {
        self
            .padding(PageChrome.padding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Transport styling

extension TransportStatusLevel {
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .connected: return .green
        case .warning: return .orange
        case .error: return .red
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
                        .foregroundStyle(.green)
                }
            } else if let status = nmeaManager.latestTransportStatus, status.level != .idle {
                Label(status.message, systemImage: status.level.systemImage)
                    .foregroundStyle(status.level.color)
            } else {
                Label("Not sending — press Start (⌘R)", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Endpoint editor

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EndpointEditorView: View {
    @Bindable var nmeaManager: NMEASimulator
    @Binding var endpoint: OutputEndpoint
    let isPrimary: Bool

    var body: some View {
        let status = nmeaManager.transportStatus(for: endpoint.id)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
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
                }
            }

            if !endpoint.isEnabled {
                Label("Disabled — not sending", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status {
                Label(status.message, systemImage: status.level.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.level.color)
            } else {
                Label("No transport activity yet", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            fieldRow("Name") {
                TextField("Output Name", text: $endpoint.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            fieldRow("Transport") {
                Picker("Transport", selection: $endpoint.transport) {
                    ForEach(NetworkTransport.allCases) { transport in
                        Text(transport.rawValue.uppercased()).tag(transport)
                    }
                }
                .labelsHidden()
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
            }

            fieldRow("Port") {
                DeferredNumericField(port: $endpoint.port, width: 120)
            }

            if isPrimary {
                fieldRow("Talker ID") {
                    TextField("Talker ID", text: $nmeaManager.talkerID)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                        .disabled(nmeaManager.selectedProfile != .custom)
                }

                Text("3 characters, e.g. II or GP. Per-sentence talkers follow the hardware profile unless Custom.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sensor grid

struct SensorToggleGrid: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        // Adaptive columns avoid ViewThatFits clipping inside Form scroll content.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
            spacing: 12
        ) {
            SensorToggleGroup(title: "Navigation Instruments", icon: "safari", toggles: [
                ("Anemometer", $nmeaManager.sensorToggles.hasAnemometer),
                ("Magnetic Compass", $nmeaManager.sensorToggles.hasCompass),
                ("Gyro Compass", $nmeaManager.sensorToggles.hasGyro),
            ])
            SensorToggleGroup(title: "Hydro Sensors", icon: "drop.triangle", toggles: [
                ("Echo Sounder", $nmeaManager.sensorToggles.hasEchoSounder),
                ("Speed Log", $nmeaManager.sensorToggles.hasSpeedLog),
                ("Water Temperature", $nmeaManager.sensorToggles.hasWaterTempSensor),
            ])
            SensorToggleGroup(title: "Environmental Sensors", icon: "thermometer.sun.circle", toggles: [
                ("Air Temperature", $nmeaManager.sensorToggles.hasAirTempSensor),
                ("Humidity", $nmeaManager.sensorToggles.hasHumidtySensor),
                ("Barometer", $nmeaManager.sensorToggles.hasBarometer),
            ])
            SensorToggleGroup(title: "Positioning", icon: "location", toggles: [
                ("GPS", $nmeaManager.sensorToggles.hasGPS),
            ])
        }
    }
}

struct SensorToggleGroup: View {
    let title: String
    let icon: String
    let toggles: [(String, Binding<Bool>)]

    var body: some View {
        GroupBox(label: Label(title, systemImage: icon)) {
            VStack(spacing: 12) {
                ForEach(toggles.indices, id: \.self) { i in
                    ViewKit.ToggleRowWithInfo(toggles[i].0, isOn: toggles[i].1)
                }
            }
            .padding(6)
        }
    }
}

// MARK: - Weather helpers

enum WeatherStatusStyle {
    static func color(for state: LiveWeatherStatusState) -> Color {
        switch state {
        case .idle: return .secondary
        case .fetching: return .blue
        case .ready: return .green
        case .failed: return .orange
        }
    }

    static func systemImage(for state: LiveWeatherStatusState) -> String {
        switch state {
        case .idle: return "cloud"
        case .fetching: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    static func weatherValue(_ value: Double?, unit: String) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

// MARK: - Advanced sections

struct RecentTransportEventsSection: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing) {
            Label("Recent Transport Events", systemImage: "waveform.path.ecg")
                .font(.headline)

            if nmeaManager.transportHistory.isEmpty {
                Text("No transport events recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nmeaManager.transportHistory.suffix(8).reversed()) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label("", systemImage: event.level.systemImage)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(event.level.color)
                        Text(event.timestamp, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(event.message)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FaultInjectionSection: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.spacing * 2) {
            Label("Fault Injection", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.headline)

            Toggle("Enable Fault Injection", isOn: $nmeaManager.faultInjection.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.regular)

            Text("Inject controlled faults to test how receivers handle bad or imperfect NMEA traffic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(horizontalSpacing: 16, verticalSpacing: UIConstants.spacing) {
                GridRow {
                    Text("Drop Rate")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.dropRate)
                    Text("Delay Rate")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.delayRate)
                }
                GridRow {
                    Text("Checksum Corruption")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.checksumCorruptionRate)
                    Text("Invalid Data Rate")
                    FaultInjectionPercentageStepper(value: $nmeaManager.faultInjection.invalidDataRate)
                }
                GridRow {
                    Text("Max Delay Cycles")
                    Stepper(value: $nmeaManager.faultInjection.maximumDelayCycles, in: 1...5) {
                        Text("\(nmeaManager.faultInjection.maximumDelayCycles)")
                            .monospacedDigit()
                    }
                    .disabled(!nmeaManager.faultInjection.isEnabled)
                }
            }
            .disabled(!nmeaManager.faultInjection.isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FaultInjectionPercentageStepper: View {
    @Binding var value: Double

    var body: some View {
        Stepper(value: $value, in: 0...0.9, step: 0.05) {
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OpenSimulationSensorsButton: View {
    @Environment(\.sidebarNavigation) private var sidebarNavigation

    var body: some View {
        Button("Open Simulation → Sensors") {
            sidebarNavigation?.select(.simulation)
        }
        .buttonStyle(.link)
        .font(.caption2)
    }
}
