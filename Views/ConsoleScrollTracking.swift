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
