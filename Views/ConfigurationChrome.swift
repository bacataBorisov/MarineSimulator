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
    var participates: Bool
    var slot: String
    @Environment(\.consoleDragTracking) private var dragTracking
    @Environment(\.pagePresentation) private var presentation
    @Environment(\.pageScrollIdentity) private var page

    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay(alignment: .topLeading) {
                ConsoleEdgeScrollBridge(
                    participates: participates,
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
    var participates: Bool
    var dragTracking: ConsoleDragTracking
    var presentation: PagePresentationSession
    var page: SidebarItem?
    var slot: String

    func makeNSView(context: Context) -> ConsoleEdgeAnchorView {
        let view = ConsoleEdgeAnchorView(
            dragTracking: dragTracking,
            presentation: presentation,
            page: page,
            slot: slot
        )
        view.setConsoleEdgeParticipation(participates)
        return view
    }

    func updateNSView(_ view: ConsoleEdgeAnchorView, context: Context) {
        view.dragTracking = dragTracking
        view.presentation = presentation
        view.noteEnvironmentIdentity(page: page, slot: slot)
        view.setConsoleEdgeParticipation(participates)
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
    private var participates = true
    private var observersInstalled = false
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
        guard participates, retainedPageIsActive else { return }
        bindIfNeeded()
        followViewport()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// False once participation is suspended. The anchor view can stay in a retained page
    /// without remaining bound to that page's clip view.
    var isBoundToConsoleEdge: Bool { scrollView != nil }

    /// Binds while this page is the shell destination. Suspending captures the current
    /// document offset, then ignores later viewport and console-drag callbacks.
    func setConsoleEdgeParticipation(_ enabled: Bool) {
        let resolved = enabled && retainedPageIsActive
        guard resolved != participates else { return }
        if resolved {
            guard !retired else { return }
            participates = true
            isDetaching = false
            didRestore = false
            previous = nil
            dragBaseline = nil
            echoViewport = nil
            echoOrigin = nil
            lastProgrammaticOrigin = nil
            lastProgrammaticViewport = nil
            bindIfNeeded()
        } else {
            rememberVisibleOffset()
            participates = false
            unregisterConsoleEdgeObservers()
            #if DEBUG
            scrollTrace.unbindAnchor(self)
            #endif
            scrollView = nil
            dragBaseline = nil
            previous = nil
            echoViewport = nil
            echoOrigin = nil
        }
    }

    func bindIfNeeded() {
        guard participates, scrollView == nil, let found = enclosingScrollView else { return }
        scrollView = found
        found.contentView.postsBoundsChangedNotifications = true
        found.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: found.contentView)
        center.addObserver(self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: found)
        center.addObserver(self, selector: #selector(userDidLiveScroll), name: NSScrollView.didLiveScrollNotification, object: found)
        observersInstalled = true
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
        guard participates else { return }
        followViewport()
    }

    /// Posted after a user event changes the clip origin. Legacy scroll wheels post this without a
    /// `willStart`/`didEnd` pair. Those session notifications also stay active for a whole trackpad
    /// gesture, so a layout callback in between must not use them.
    @objc private func userDidLiveScroll(_ notification: Notification) {
        guard participates, dragTracking.isDragging, !isApplying, !retired, !isDetaching else { return }
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
        guard participates else { return }
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
        rememberVisibleOffset()
    }

    private func unregisterConsoleEdgeObservers() {
        guard observersInstalled else { return }
        NotificationCenter.default.removeObserver(self)
        observersInstalled = false
    }

    private func rememberVisibleOffset() {
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

    /// A retained host owns activity. Pages without one stay active.
    private var retainedPageIsActive: Bool {
        var current: NSView? = superview
        while let node = current {
            if let host = node as? any RetainedDestinationHosting {
                return host.isPageActive
            }
            current = node.superview
        }
        return true
    }
}

extension View {
    /// Tracks the shell console from inside this scrolling content, and restores that scroller for its page slot.
    /// Do not use it on the dashboard map.
    /// Pass `false` for every row except one, so a list does not adjust the same drag twice.
    /// `slot` distinguishes nested scrollers on one sidebar page. The page itself comes from the environment.
    func tracksConsoleEdge(_ enabled: Bool = true, participates: Bool = true, slot: String = "primary") -> some View {
        modifier(ConsoleEdgeScrollTracking(isEnabled: enabled, participates: participates && enabled, slot: slot))
    }
}

#if DEBUG
/// Counts evaluations of a retained page body. Selection must not increment it.
enum RetainedDestinationBodyProbe {
    static var connectionEvaluations = 0
    static var simulationEvaluations = 0
    static var boatEvaluations = 0
    static var timerStatusEvaluations = 0
    static var timerStatus = ""
    static var timerStatusCard: String?
    static var intervalLabel = ""
    static var readings: [String: String] = [:]

    static func record(_ page: SidebarItem) {
        switch page {
        case .connection: connectionEvaluations += 1
        case .simulation: simulationEvaluations += 1
        case .boat: boatEvaluations += 1
        default: break
        }
    }

    static func noteTimerStatus(_ status: String, card: String?) {
        timerStatusEvaluations += 1
        timerStatus = status
        timerStatusCard = card
    }

    static func noteInterval(_ label: String) {
        intervalLabel = label
    }

    static func noteReading(_ title: String, _ label: String) {
        readings[title] = label
    }
}
private struct SettingsCardIdentityKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Debug-only identity of the enclosing `SettingsCard`, used to prove which card contains a child.
    var settingsCardIdentity: String? {
        get { self[SettingsCardIdentityKey.self] }
        set { self[SettingsCardIdentityKey.self] = newValue }
    }
}
#endif

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
        .background(DesignToken.Surface.page)
    }
}

/// Zero-size identity token for a destination whose SwiftUI tree stays mounted.
struct RetainedDestinationMarker: NSViewRepresentable {
    var page: SidebarItem

    func makeNSView(context: Context) -> RetainedDestinationMarkerView {
        RetainedDestinationMarkerView(page: page)
    }

    func updateNSView(_ nsView: RetainedDestinationMarkerView, context: Context) {}
}

final class RetainedDestinationMarkerView: NSView {
    let page: SidebarItem

    init(page: SidebarItem) {
        self.page = page
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension View {
    func pageContentFrame(maxWidth: CGFloat = PageChrome.maxWidth) -> some View {
        self
            .padding(PageChrome.padding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Responsive layout

/// Content-width classes for setup pages.
/// `contentWidth` is the width proposed to the page body after the page inset.
/// Sidebar, toolbar, and console can make that width smaller than the 960×640 window.
/// These classes do not promise a content height. Pages scroll.
enum ContentWidthClass: Equatable {
    /// Available content below 720 points.
    case compact
    /// From 720 up to, but not including, two minimum configuration cards.
    case regular
    /// 900 points and above: 440 + 20 + 440.
    case wide
}

/// Layout names for `DesignToken`. Width class uses available page content, not the window.
enum ResponsiveLayout {
    static let targetMinimumContentWidth = DesignToken.Breakpoint.regular

    static let configurationGutter = DesignToken.Spacing.section
    static let configurationCardMinimum = DesignToken.Width.configurationCardMinimum
    static let configurationCardMaximum = DesignToken.Width.configurationCardMaximum
    /// Page column maximum for Connection and Simulation, including the page inset.
    static let adaptivePageMaxWidth = DesignToken.Width.adaptivePage

    static let formLabelWidth = DesignToken.Form.labelWidth
    static let formColumnGap = DesignToken.Spacing.field
    static let formValueMinimum = DesignToken.Form.valueMinimum
    static let formValueIdeal = DesignToken.Form.valueIdeal
    static let formValueMaximum = DesignToken.Form.valueMaximum
    static let formStackedSpacing = DesignToken.Spacing.stacked

    static var twoColumnContentWidth: CGFloat {
        configurationCardMinimum * 2 + configurationGutter
    }

    static var formRowCompactWidth: CGFloat {
        formLabelWidth + formColumnGap + formValueMinimum
    }

    /// Inner width of an adaptive page at `adaptivePageMaxWidth`.
    static var adaptiveContentWidth: CGFloat {
        adaptivePageMaxWidth - PageChrome.padding * 2
    }

    static func widthClass(for contentWidth: CGFloat) -> ContentWidthClass {
        if contentWidth < targetMinimumContentWidth { return .compact }
        if contentWidth < twoColumnContentWidth { return .regular }
        return .wide
    }

    static func formRowStyle(for availableWidth: CGFloat) -> FormRowStyle {
        availableWidth >= formRowCompactWidth ? .compactGrid : .stacked
    }

    static func formValueColumnWidth(for rowWidth: CGFloat) -> CGFloat {
        guard formRowStyle(for: rowWidth) == .compactGrid else {
            return min(formValueMaximum, max(0, rowWidth))
        }
        let remaining = rowWidth - formLabelWidth - formColumnGap
        return min(formValueMaximum, max(formValueMinimum, remaining))
    }
}

enum FormRowStyle: Equatable {
    /// Trailing label column, gap, leading value column.
    case compactGrid
    /// Label above the value. Used when the row cannot hold the compact grid.
    case stacked
}

/// Accessibility contract for a boat or sail measurement row.
enum FormRowAccessibility {
    static func editorLabel(_ title: String) -> String { title }
    /// A read-only row keeps its visible title. An editor hides that title from accessibility
    /// and puts the same string on the field, so the label is not announced twice.
    static let readOnlyKeepsVisibleTitle = true
    /// A measurement unit is placed in the value column, beside the editor.
    static let unitStaysBesideValue = true

    static func layoutStyle(for availableWidth: CGFloat) -> FormRowStyle {
        ResponsiveLayout.formRowStyle(for: availableWidth)
    }
}

/// Accessibility identifiers for Connection and Simulation cards.
enum SetupSection: String, Equatable {
    case connectionHealth
    case connectionWarning
    case primaryOutput
    case transmission
    case additionalOutputs
    case hardwareProfile
    case sentenceUpdateRates
    case testPresets
    case weatherSource
    case onboardSensors
    case advancedControls
}

/// Toolbar title and the decision not to repeat it in the page body.
enum PageTitlePresentation {
    static func toolbarTitle(for item: SidebarItem) -> String {
        item.pageTitle
    }

    /// Sidebar pages take their title from the toolbar. Section headings stay in the page.
    static func inContentPageTitle(for item: SidebarItem) -> String? {
        _ = item
        return nil
    }

    static let shellOwnsTopSeparator = true
}

/// The shell detail column owns the single separator under the toolbar.
enum ShellChrome {
    static let topSeparatorHeight: CGFloat = 1
    static let pagesAddTopSeparator = false
}

struct ShellContentTopSeparator: View {
    var body: some View {
        Rectangle()
            .fill(DesignToken.Separator.standard)
            .frame(height: ShellChrome.topSeparatorHeight)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// One label and one value. Narrow rows stack. Wider rows keep the label column.
/// Only the fitting branch is built, so an editor is not created twice.
struct CompactFormRow<Value: View>: View {
    var title: String
    var editor: Bool = false
    @ViewBuilder var value: () -> Value
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        let stacked = rowWidth > 0 && FormRowAccessibility.layoutStyle(for: rowWidth) == .stacked
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: ResponsiveLayout.formStackedSpacing) {
                    rowLabel
                    value()
                        .frame(maxWidth: ResponsiveLayout.formValueMaximum, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: ResponsiveLayout.formColumnGap) {
                    rowLabel
                        .frame(width: ResponsiveLayout.formLabelWidth, alignment: .trailing)
                    value()
                        .frame(
                            minWidth: ResponsiveLayout.formValueMinimum,
                            maxWidth: ResponsiveLayout.formValueMaximum,
                            alignment: .leading
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
            let nextStacked = newWidth > 0 && FormRowAccessibility.layoutStyle(for: newWidth) == .stacked
            let currentStacked = rowWidth > 0 && FormRowAccessibility.layoutStyle(for: rowWidth) == .stacked
            if rowWidth == 0 || nextStacked != currentStacked {
                rowWidth = newWidth
            }
        }
    }

    private var rowLabel: some View {
        Text(title)
            .font(DesignToken.Typography.field)
            .foregroundStyle(.secondary)
            .accessibilityHidden(editor)
    }
}

/// Compact and Regular are one column. Wide is two columns plus full-width bands.
/// The unused branch is not built. State stays in the observable model and the retained root.
struct SetupColumns<Compact: View, Wide: View>: View {
    @State private var contentWidth: CGFloat = 0
    @ViewBuilder var compact: () -> Compact
    @ViewBuilder var wide: () -> Wide

    private var isWide: Bool {
        contentWidth >= ResponsiveLayout.twoColumnContentWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
            if isWide {
                wide()
            } else {
                compact()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
            guard newWidth > 1 else { return }
            let nextWide = newWidth >= ResponsiveLayout.twoColumnContentWidth
            let currentWide = contentWidth >= ResponsiveLayout.twoColumnContentWidth
            if contentWidth == 0 || nextWide != currentWide {
                contentWidth = newWidth
            }
        }
    }
}

/// Text field with one persistent external label. An optional unit stays beside the value.
struct FormTextRow: View {
    var title: String
    @Binding var text: String
    var accessibilityLabel: String?
    var unit: String?

    private var label: String { accessibilityLabel ?? FormRowAccessibility.editorLabel(title) }

    var body: some View {
        CompactFormRow(title: title, editor: true) {
            if let unit {
                HStack(spacing: DesignToken.Spacing.related) {
                    field
                        .frame(minWidth: DesignToken.Form.editorMinimum, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(unit)
                        .font(DesignToken.Typography.field)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                field
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var field: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(DesignToken.Typography.field)
            .labelsHidden()
            .accessibilityLabel(label)
            .accessibilityIdentifier(label)
            .multilineTextAlignment(.leading)
    }
}

/// Menu picker with one persistent external label and the same label on the control.
struct FormMenuRow<Selection: Hashable, Content: View>: View {
    var title: String
    var accessibilityLabel: String?
    @Binding var selection: Selection
    var isEnabled: Bool = true
    @ViewBuilder var content: () -> Content

    private var label: String { accessibilityLabel ?? FormRowAccessibility.editorLabel(title) }

    var body: some View {
        CompactFormRow(title: title, editor: true) {
            Picker(label, selection: $selection, content: content)
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityIdentifier(label)
                .pickerStyle(.menu)
                .disabled(!isEnabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

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

// MARK: - Endpoint editor

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
/// The synchronous AppKit tree does not expose SwiftUI heading traits.
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

// MARK: - Sensor grid

struct SensorToggleGrid: View {
    @Bindable var nmeaManager: NMEASimulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    HStack {
                        Text(toggles[i].0)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(toggles[i].0)
                        Spacer()
                        Toggle("", isOn: toggles[i].1)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .accessibilityLabel(toggles[i].0)
                    }
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
        case .idle: return DesignToken.Status.neutral
        case .fetching: return DesignToken.Status.info
        case .ready: return DesignToken.Status.success
        case .failed: return DesignToken.Status.warning
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
