import Testing
import AppKit
@testable import MarineSimulator

@Suite
@MainActor
struct PagePresentationTests {

    @Test
    func returningToAPageRestoresItsScrollAndLeavesTheOtherPageAlone() {
        let session = PagePresentationSession()
        let diagnostics = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 500)
        diagnostics.userScroll(to: 640)
        let simulation = PageScrollMemoryRig(session: session, page: .simulation, contentHeight: 2400, viewport: 500)
        simulation.userScroll(to: 180)

        let returned = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 500)
        expectNear(returned.offset, 640)
        expectNear(simulation.offset, 180)
        expectNear(session.storedOffset(page: .simulation, slot: "primary") ?? -1, 180)
    }

    @Test
    func theFirstVisitStaysAtTheInitialOffset() {
        let session = PagePresentationSession()
        let first = PageScrollMemoryRig(session: session, page: .connection, contentHeight: 2400, viewport: 500)
        expectNear(first.offset, 0)
        #expect(session.storedOffset(page: .boat, slot: "primary") == nil)
    }

    @Test
    func nestedSlotsOnOnePageRestoreIndependently() {
        let session = PagePresentationSession()
        let sentences = PageScrollMemoryRig(session: session, page: .wind, slot: "sentences", contentHeight: 2400, viewport: 500)
        let preview = PageScrollMemoryRig(session: session, page: .wind, slot: "preview", contentHeight: 1800, viewport: 500)
        sentences.userScroll(to: 420)
        preview.userScroll(to: 90)

        let sentencesAgain = PageScrollMemoryRig(session: session, page: .wind, slot: "sentences", contentHeight: 2400, viewport: 500)
        let previewAgain = PageScrollMemoryRig(session: session, page: .wind, slot: "preview", contentHeight: 1800, viewport: 500)
        expectNear(sentencesAgain.offset, 420)
        expectNear(previewAgain.offset, 90)
    }

    @Test
    func expandedAndCollapsedViewportsRestoreTheSameDocumentPoint() {
        let session = PagePresentationSession()
        let page = PageScrollMemoryRig(session: session, page: .manual, slot: "body", contentHeight: 2400, viewport: 500)
        page.userScroll(to: 800)

        let expandedConsole = PageScrollMemoryRig(
            session: session,
            page: .manual,
            slot: "body",
            contentHeight: 2400,
            viewport: 300
        )
        let collapsedConsole = PageScrollMemoryRig(
            session: session,
            page: .manual,
            slot: "body",
            contentHeight: 2400,
            viewport: 700
        )
        expectNear(expandedConsole.offset, 800)
        expectNear(collapsedConsole.offset, 800)
        #expect(expandedConsole.tracking.isDragging == false)
        #expect(collapsedConsole.tracking.isDragging == false)
    }

    @Test
    func aShorterDocumentClampsTheVisibleOffsetAndKeepsTheStoredPoint() {
        let session = PagePresentationSession()
        let page = PageScrollMemoryRig(session: session, page: .hydro, contentHeight: 2400, viewport: 400)
        page.userScroll(to: 900)

        let shorter = PageScrollMemoryRig(session: session, page: .hydro, contentHeight: 1000, viewport: 400)
        expectNear(shorter.offset, 600)
        expectNear(session.storedOffset(page: .hydro, slot: "primary") ?? -1, 900)

        let taller = PageScrollMemoryRig(session: session, page: .hydro, contentHeight: 2400, viewport: 400)
        expectNear(taller.offset, 900)
    }

    @Test
    func aConsoleDragStillMovesFromTheRestoredOffset() {
        let session = PagePresentationSession()
        let page = PageScrollMemoryRig(session: session, page: .compass, contentHeight: 2400, viewport: 500)
        page.userScroll(to: 400)
        let returned = PageScrollMemoryRig(session: session, page: .compass, contentHeight: 2400, viewport: 500)
        expectNear(returned.offset, 400)
        #expect(returned.tracking.isDragging == false)

        returned.setViewport(400)
        returned.anchor.followViewport()
        expectNear(returned.offset, 400)

        returned.tracking.isDragging = true
        returned.setViewport(350)
        returned.anchor.followViewport()
        expectNear(returned.offset, 450)
    }

    @Test
    func leavingThePageKeepsTheOffsetWhenTheClipIsThenZeroed() {
        let session = PagePresentationSession()
        let page = PageScrollMemoryRig(session: session, page: .gps, slot: "stacked", contentHeight: 2400, viewport: 500)
        page.userScroll(to: 510)
        page.anchor.captureForDeparture()
        page.setViewport(500, offset: 0)
        page.anchor.followViewport()

        let returned = PageScrollMemoryRig(session: session, page: .gps, slot: "stacked", contentHeight: 2400, viewport: 500)
        expectNear(returned.offset, 510)
    }

    @Test
    func theDashboardDoesNotAlsoUseTheShellConsole() {
        #expect(SidebarItem.dashboard.placesConsoleInTheShell == false)
        #expect(SidebarItem.diagnostics.placesConsoleInTheShell)
    }

    /// Regression: UI.1e wrote the next clip sample under the sidebar item that was current when the callback ran.
    @Test
    func aLateIdentityChangeCannotRewriteEitherPage() {
        let session = PagePresentationSession()
        let diagnostics = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 500)
        diagnostics.userScroll(to: 600)
        diagnostics.anchor.noteEnvironmentIdentity(page: .simulation, slot: "primary")
        diagnostics.setViewport(500, offset: 0)
        diagnostics.anchor.followViewport()
        diagnostics.userScroll(to: 300)

        expectNear(session.storedOffset(page: .diagnostics, slot: "primary") ?? -1, 600)
        #expect(session.storedOffset(page: .simulation, slot: "primary") == nil)

        let simulation = PageScrollMemoryRig(session: session, page: .simulation, contentHeight: 2400, viewport: 500)
        simulation.userScroll(to: 300)
        let diagnosticsAgain = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 500)
        expectNear(diagnosticsAgain.offset, 600)
        expectNear(simulation.offset, 300)
    }

    @Test
    func repeatedNavigationKeepsEachPageAtItsOwnOffset() {
        let session = PagePresentationSession()
        for _ in 0..<3 {
            let diagnostics = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 420)
            diagnostics.userScroll(to: 600)
            diagnostics.anchor.noteEnvironmentIdentity(page: .simulation, slot: "primary")
            let simulation = PageScrollMemoryRig(session: session, page: .simulation, contentHeight: 2400, viewport: 420)
            simulation.userScroll(to: 300)
            simulation.anchor.noteEnvironmentIdentity(page: .diagnostics, slot: "primary")
        }
        let diagnostics = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 300)
        let simulation = PageScrollMemoryRig(session: session, page: .simulation, contentHeight: 2400, viewport: 700)
        expectNear(diagnostics.offset, 600)
        expectNear(simulation.offset, 300)
    }

    @Test
    func anUnidentifiedLayoutCannotEraseAStoredOffset() {
        let session = PagePresentationSession()
        session.remember(600, page: .diagnostics, slot: "primary")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 2400))
        scroll.documentView = document
        var bounds = scroll.contentView.bounds
        bounds.size.height = 500
        bounds.origin.y = 0
        scroll.contentView.bounds = bounds
        let anchor = ConsoleEdgeAnchorView(dragTracking: ConsoleDragTracking(), presentation: session, page: nil)
        document.addSubview(anchor)
        anchor.bindIfNeeded()
        anchor.followViewport()
        expectNear(scroll.contentView.bounds.origin.y, 0)
        expectNear(session.storedOffset(page: .diagnostics, slot: "primary") ?? -1, 600)

        anchor.noteEnvironmentIdentity(page: .diagnostics, slot: "primary")
        anchor.followViewport()
        expectNear(scroll.contentView.bounds.origin.y, 600)
        expectNear(session.storedOffset(page: .diagnostics, slot: "primary") ?? -1, 600)
    }

    /// Regression: UI.1e added each viewport change to the last offset, so a reset or a clamp in the middle of the gesture did not come back.
    @Test
    func aBottomRoundTripReturnsAfterAnOriginReset() {
        let session = PagePresentationSession()
        let other = PageScrollMemoryRig(session: session, page: .simulation, contentHeight: 2400, viewport: 500)
        other.userScroll(to: 222)
        let page = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2000, viewport: 500)
        page.userScroll(to: 1500)
        page.tracking.isDragging = true

        page.setViewport(360)
        page.anchor.followViewport()
        expectNear(page.offset, 1640)

        page.setViewport(360, offset: 1500)
        page.anchor.followViewport()
        expectNear(page.offset, 1500)

        page.setViewport(500)
        page.anchor.followViewport()
        expectNear(page.offset, 1500)
        expectNear(session.storedOffset(page: .simulation, slot: "primary") ?? -1, 222)
    }

    @Test
    func aMidPageRoundTripReturnsToTheGestureStart() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .connection,
            contentHeight: 1000,
            viewport: 400,
            offset: 40
        )
        page.tracking.isDragging = true
        page.setViewport(980)
        page.anchor.followViewport()
        expectNear(page.offset, 0)
        page.setViewport(400)
        page.anchor.followViewport()
        expectNear(page.offset, 40)
    }

    @Test
    func repeatedBottomDragsDoNotDrift() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .hydro,
            contentHeight: 2000,
            viewport: 500,
            offset: 1500
        )
        for _ in 0..<4 {
            page.tracking.isDragging = true
            page.setViewport(280)
            page.anchor.followViewport()
            expectNear(page.offset, 1720)
            page.setViewport(500)
            page.anchor.followViewport()
            expectNear(page.offset, 1500)
            page.tracking.isDragging = false
            page.anchor.followViewport()
        }
    }

    @Test
    func aSmallViewportChangeStillRoundTrips() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .compass,
            contentHeight: 2000,
            viewport: 500,
            offset: 1500
        )
        page.tracking.isDragging = true
        page.setViewport(498)
        page.anchor.followViewport()
        expectNear(page.offset, 1502)
        page.setViewport(500)
        page.anchor.followViewport()
        expectNear(page.offset, 1500)
    }

    @Test
    func aManualScrollDuringTheDragBecomesTheBaseline() {
        let page = PageScrollMemoryRig(session: PagePresentationSession(), page: .wind, slot: "sentences", contentHeight: 2400, viewport: 500)
        page.userScroll(to: 400)
        page.tracking.isDragging = true
        page.setViewport(400)
        page.anchor.followViewport()
        expectNear(page.offset, 500)
        page.userScroll(to: 550)
        page.setViewport(350)
        page.anchor.followViewport()
        expectNear(page.offset, 600)
    }

    @Test
    func aConsoleDragOnOnePageLeavesTheOtherPageStored() {
        let session = PagePresentationSession()
        let tracking = ConsoleDragTracking()
        let diagnostics = PageScrollMemoryRig(session: session, page: .diagnostics, contentHeight: 2400, viewport: 500, tracking: tracking)
        let simulation = PageScrollMemoryRig(session: session, page: .simulation, contentHeight: 2400, viewport: 500, tracking: tracking)
        diagnostics.userScroll(to: 600)
        simulation.userScroll(to: 300)
        tracking.isDragging = true
        simulation.setViewport(380)
        simulation.anchor.followViewport()
        diagnostics.anchor.followViewport()
        expectNear(simulation.offset, 420)
        expectNear(diagnostics.offset, 600)
        expectNear(session.storedOffset(page: .diagnostics, slot: "primary") ?? -1, 600)
    }

    @Test
    func documentGrowthKeepsABottomAnchorAndLeavesAMidPageAnchor() {
        let session = PagePresentationSession()
        let bottom = PageScrollMemoryRig(session: session, page: .gps, slot: "stacked", contentHeight: 1000, viewport: 400, offset: 600)
        let middle = PageScrollMemoryRig(session: session, page: .gps, slot: "preview", contentHeight: 2400, viewport: 500, offset: 400)
        bottom.tracking.isDragging = true
        middle.tracking.isDragging = true
        bottom.setContentHeight(1300)
        middle.setContentHeight(3000)
        bottom.anchor.followViewport()
        middle.anchor.followViewport()
        expectNear(bottom.offset, 900)
        expectNear(middle.offset, 400)
    }

    /// Regression: AppKit writes a new clip origin while the viewport height is still the old one, then updates the height.
    @Test
    func anOriginChangeBeforeTheViewportDoesNotReplaceTheGestureBaseline() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .connection,
            contentHeight: 1369,
            viewport: 530,
            offset: 390
        )
        page.tracking.isDragging = true

        page.setViewport(530, offset: 401.5)
        page.anchor.followViewport()
        expectNear(page.offset, 401.5)

        page.setViewport(518.5)
        page.anchor.followViewport()
        expectNear(page.offset, 401.5)

        page.setViewport(518.5, offset: 420)
        page.anchor.followViewport()
        expectNear(page.offset, 420)

        page.setViewport(530)
        page.anchor.followViewport()
        expectNear(page.offset, 390)
    }

    /// Regression: the live clip origin can be the inset minimum, below zero. A 9-point shrink must not jump to 0.
    @Test
    func aNegativeMinimumOriginRoundTripsAcrossExpandAndContract() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .connection,
            contentHeight: 1369,
            viewport: 966,
            bottomInset: 46
        )
        let minimum = page.limits(viewport: 966).minimum
        #expect(minimum < -1)
        page.scrollOrigin(to: minimum)
        expectNear(page.offset, minimum)

        page.tracking.isDragging = true
        page.setViewport(966, offset: 0)
        page.anchor.followViewport()
        expectNear(page.offset, 0)

        page.setViewport(957)
        page.anchor.followViewport()
        expectNear(page.offset, minimum + 9)

        page.setViewport(957, offset: 0)
        page.anchor.followViewport()
        expectNear(page.offset, 0)

        page.setViewport(966)
        page.anchor.followViewport()
        expectNear(page.offset, minimum)
    }

    /// Rubber-band overscroll sits past the inset minimum. `scroll(to:)` can park the bounds there,
    /// but that origin is not a document point and the overlay scroller cannot represent it.
    /// The gesture keeps the legal minimum (-52 when the bottom inset is 52).
    @Test
    func aRubberBandOriginBelowTheInsetMinimumIsNotRestored() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .connection,
            contentHeight: 1369,
            viewport: 966,
            bottomInset: 52
        )
        let minimum = page.limits(viewport: 966).minimum
        expectNear(minimum, -52)
        page.scrollOrigin(to: minimum)
        expectNear(page.offset, minimum)

        page.tracking.isDragging = true
        page.scroll.contentView.scroll(to: NSPoint(x: 0, y: minimum - 6))
        expectNear(page.offset, minimum - 6)
        let afterOverscroll = page.writtenOrigins.count
        page.anchor.followViewport()
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: page.scroll)
        expectNear(page.offset, minimum - 6)

        page.setViewport(957)
        page.anchor.followViewport()
        expectNear(page.offset, minimum + 9)

        page.setViewport(966)
        page.anchor.followViewport()
        expectNear(page.offset, minimum)
        #expect(page.writtenOrigins.dropFirst(afterOverscroll).allSatisfy { $0 >= minimum - 0.5 })
    }

    /// Regression: a bottom-pinned page stays pinned when the origin moves before the viewport does.
    @Test
    func aBottomPinRoundTripsWhenTheOriginChangesBeforeTheViewport() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .connection,
            contentHeight: 1369,
            viewport: 530,
            topInset: 15
        )
        let start = page.limits(viewport: 530).maximum
        #expect(abs(start - (1369 - 530)) > 1)
        page.scrollOrigin(to: start)
        expectNear(page.offset, start)

        page.tracking.isDragging = true
        let writesAtStart = page.scrollWriteCount
        page.setViewport(530, offset: start - 11.5)
        page.anchor.followViewport()
        expectNear(page.offset, start - 11.5)
        #expect(page.scrollWriteCount == writesAtStart)

        page.setViewport(500)
        page.anchor.followViewport()
        let contracted = page.limits(viewport: 500).maximum
        expectNear(page.offset, contracted)
        #expect(page.scrollWriteCount == writesAtStart + 1)

        page.setViewport(500, offset: contracted - 11.5)
        page.anchor.followViewport()
        expectNear(page.offset, contracted - 11.5)
        #expect(page.scrollWriteCount == writesAtStart + 1)

        let beforeReturn = page.scrollWriteCount
        page.setViewport(530)
        page.anchor.followViewport()
        expectNear(page.offset, start)
        // Growing the viewport can clamp the live origin onto the new maximum before the bridge writes.
        #expect(page.scrollWriteCount - beforeReturn <= 1)
    }

    @Test
    func aLiveUserScrollRebasesButALayoutOriginDoesNot() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .wind,
            slot: "sentences",
            contentHeight: 2400,
            viewport: 500
        )
        page.userScroll(to: 400)
        page.tracking.isDragging = true
        page.setViewport(400)
        page.anchor.followViewport()
        expectNear(page.offset, 500)

        page.setViewport(400, offset: 560)
        page.anchor.followViewport()
        expectNear(page.offset, 560)

        page.userScroll(to: 550)
        page.setViewport(350)
        page.anchor.followViewport()
        expectNear(page.offset, 600)
    }

    /// The captured contraction step moved the origin twice before the viewport. The old bridge wrote
    /// a correction for each of those, then wrote again for the height. One console step now writes once.
    @Test
    func anOriginBeforeViewportSequenceWritesTheFinalTargetOnce() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .connection,
            contentHeight: 1369,
            viewport: 966,
            offset: -52,
            bottomInset: 52
        )
        let minimum = page.limits(viewport: 966).minimum
        expectNear(minimum, -52)
        expectNear(page.offset, minimum)
        expectNear((1369 - 966) - page.offset, 455)

        page.tracking.isDragging = true
        let before = page.scrollWriteCount
        page.setViewport(966, offset: 40)
        page.anchor.followViewport()
        page.setViewport(966, offset: -10)
        page.anchor.followViewport()
        page.setViewport(966, offset: 80)
        page.anchor.followViewport()
        #expect(page.scrollWriteCount == before)

        page.setViewport(900)
        page.anchor.followViewport()
        #expect(page.scrollWriteCount == before + 1)
        expectNear(page.offset, 14)
        expectNear((1369 - 900) - page.offset, 455)

        let atExpanded = page.scrollWriteCount
        page.setViewport(900, offset: 44)
        page.anchor.followViewport()
        page.setViewport(900, offset: -6)
        page.anchor.followViewport()
        #expect(page.scrollWriteCount == atExpanded)

        page.setViewport(966)
        page.anchor.followViewport()
        #expect(page.scrollWriteCount == atExpanded + 1)
        expectNear(page.offset, minimum)
        expectNear((1369 - 966) - page.offset, 455)
    }

    /// `willStart`/`didEnd` bracket a whole trackpad gesture and miss a legacy wheel.
    /// Only `didLiveScrollNotification`, after the origin change, may replace the baseline.
    @Test
    func aDidLiveScrollRebasesWithoutALiveScrollSession() {
        let page = PageScrollMemoryRig(
            session: PagePresentationSession(),
            page: .wind,
            slot: "sentences",
            contentHeight: 2400,
            viewport: 500
        )
        page.userScroll(to: 400)
        page.tracking.isDragging = true
        page.setViewport(400)
        page.anchor.followViewport()
        expectNear(page.offset, 500)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: page.scroll)
        page.setViewport(400, offset: 560)
        page.anchor.followViewport()
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: page.scroll)
        let writes = page.scrollWriteCount
        page.setViewport(350)
        page.anchor.followViewport()
        expectNear(page.offset, 550)
        #expect(page.scrollWriteCount == writes + 1)

        page.setViewport(350, offset: 620)
        page.anchor.followViewport()
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: page.scroll)
        page.setViewport(300)
        page.anchor.followViewport()
        expectNear(page.offset, 670)
    }

    @Test
    func aSuspendedAnchorKeepsItsOffsetAndDoesNotFollowAnotherPage() {
        let session = PagePresentationSession()
        let connection = PageScrollMemoryRig(
            session: session,
            page: .connection,
            contentHeight: 2400,
            viewport: 500
        )
        connection.userScroll(to: 480)
        connection.anchor.setConsoleEdgeParticipation(false)
        #expect(connection.anchor.isBoundToConsoleEdge == false)

        connection.setViewport(300, offset: 0)
        connection.anchor.followViewport()
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: connection.scroll)
        expectNear(session.storedOffset(page: .connection, slot: "primary") ?? -1, 480)
        expectNear(connection.offset, 0)

        let simulation = PageScrollMemoryRig(
            session: session,
            page: .simulation,
            contentHeight: 2400,
            viewport: 500
        )
        simulation.userScroll(to: 200)
        simulation.tracking.isDragging = true
        simulation.setViewport(360)
        simulation.anchor.followViewport()
        expectNear(session.storedOffset(page: .connection, slot: "primary") ?? -1, 480)
        expectNear(session.storedOffset(page: .simulation, slot: "primary") ?? -1, 340)

        connection.anchor.setConsoleEdgeParticipation(true)
        #expect(connection.anchor.isBoundToConsoleEdge)
        connection.setViewport(500, offset: 0)
        connection.anchor.followViewport()
        expectNear(connection.offset, 480)
        expectNear(session.storedOffset(page: .simulation, slot: "primary") ?? -1, 340)
        #expect(connection.tracking.isDragging == false)
    }
}

private func expectNear(_ value: CGFloat, _ expected: CGFloat) {
    #expect(abs(value - expected) < 0.5)
}

@MainActor
private final class PageScrollMemoryRig {
    let session: PagePresentationSession
    let scroll: NSScrollView
    let clip: CountingClipView
    let anchor: ConsoleEdgeAnchorView
    let tracking: ConsoleDragTracking

    init(
        session: PagePresentationSession,
        page: SidebarItem,
        slot: String = "primary",
        contentHeight: CGFloat,
        viewport: CGFloat,
        offset: CGFloat = 0,
        tracking: ConsoleDragTracking? = nil,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) {
        self.tracking = tracking ?? ConsoleDragTracking()
        self.session = session
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: viewport))
        clip = CountingClipView()
        scroll.contentView = clip
        if topInset != 0 || bottomInset != 0 {
            clip.automaticallyAdjustsContentInsets = false
            clip.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        }
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: contentHeight))
        scroll.documentView = document
        anchor = ConsoleEdgeAnchorView(
            dragTracking: self.tracking,
            presentation: session,
            page: page,
            slot: slot
        )
        document.addSubview(anchor)
        anchor.bindIfNeeded()
        setViewport(viewport, offset: offset)
        anchor.followViewport()
    }

    var offset: CGFloat { scroll.contentView.bounds.origin.y }
    var scrollWriteCount: Int { clip.scrollWriteCount }
    var writtenOrigins: [CGFloat] { clip.writtenOrigins }

    func setViewport(_ height: CGFloat, offset: CGFloat? = nil) {
        var bounds = scroll.contentView.bounds
        bounds.size.height = height
        if let offset {
            bounds.origin.y = offset
        }
        scroll.contentView.bounds = bounds
    }

    func userScroll(to y: CGFloat) {
        setViewport(scroll.contentView.bounds.height, offset: y)
        anchor.followViewport()
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
    }

    func scrollOrigin(to y: CGFloat) {
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        anchor.followViewport()
    }

    func limits(viewport: CGFloat) -> ConsoleScrollLimits {
        ConsoleScrollLimits.reading(scroll.contentView, viewportHeight: viewport)
    }

    func setContentHeight(_ height: CGFloat) {
        scroll.documentView?.setFrameSize(NSSize(width: 320, height: height))
        scroll.documentView?.bounds.size.height = height
    }
}

private final class CountingClipView: NSClipView {
    var scrollWriteCount = 0
    var writtenOrigins: [CGFloat] = []

    override func scroll(to newOrigin: NSPoint) {
        scrollWriteCount += 1
        writtenOrigins.append(newOrigin.y)
        super.scroll(to: newOrigin)
    }
}
