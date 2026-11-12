import Testing
import AppKit
@testable import MarineSimulator

@Suite
struct ShellConsoleLayoutTests {

    @Test
    func theDashboardDoesNotAlsoUseTheShellConsole() {
        #expect(SidebarItem.dashboard.placesConsoleInTheShell == false)
    }

    @Test
    func everyOtherPageUsesTheShellConsole() {
        let pages: [SidebarItem] = [
            .connection, .simulation, .boat, .diagnostics, .manual,
            .wind, .compass, .hydro, .gps
        ]
        for page in pages {
            #expect(page.placesConsoleInTheShell)
        }
    }
}

@Suite
@MainActor
struct ConsoleEdgeFollowTests {

    @Test
    func aMidPageDragKeepsTheConsoleEdgeAndTheReverseRestoresIt() {
        let rig = PageScrollRig(contentHeight: 2400, viewport: 500, offset: 400)
        let untouched = PageScrollRig(contentHeight: 2400, viewport: 500, offset: 100)
        rig.tracking.isDragging = true

        rig.setViewport(400)
        rig.anchor.followViewport()
        expectNear(rig.offset, 500)
        expectNear(untouched.offset, 100)

        rig.setViewport(500)
        rig.anchor.followViewport()
        expectNear(rig.offset, 400)
    }

    @Test
    func theOffsetStopsAtBothEnds() {
        let top = PageScrollRig(contentHeight: 2000, viewport: 400, offset: 20)
        top.tracking.isDragging = true
        top.setViewport(520)
        top.anchor.followViewport()
        expectNear(top.offset, 0)

        let bottom = PageScrollRig(contentHeight: 1000, viewport: 400, offset: 600)
        bottom.tracking.isDragging = true
        bottom.setViewport(300)
        bottom.anchor.followViewport()
        expectNear(bottom.offset, 700)
    }

    @Test
    func aShortPageAndAWindowResizeStayStill() {
        let shortPage = PageScrollRig(contentHeight: 180, viewport: 400, offset: 0)
        shortPage.tracking.isDragging = true
        shortPage.setViewport(280)
        shortPage.anchor.followViewport()
        expectNear(shortPage.offset, 0)

        let windowResize = PageScrollRig(contentHeight: 2400, viewport: 500, offset: 400)
        windowResize.setViewport(360)
        windowResize.anchor.followViewport()
        expectNear(windowResize.offset, 400)
    }

    @Test
    func aManualScrollBecomesTheNextDragBaseline() {
        let rig = PageScrollRig(contentHeight: 2400, viewport: 500, offset: 400)
        rig.setViewport(500, offset: 700)
        rig.anchor.followViewport()
        rig.tracking.isDragging = true
        rig.setViewport(450)
        rig.anchor.followViewport()
        expectNear(rig.offset, 750)
    }
}

private func expectNear(_ value: CGFloat, _ expected: CGFloat) {
    #expect(abs(value - expected) < 0.5)
}

@MainActor
private final class PageScrollRig {
    let scroll: NSScrollView
    let anchor: ConsoleEdgeAnchorView
    let tracking: ConsoleDragTracking

    init(contentHeight: CGFloat, viewport: CGFloat, offset: CGFloat) {
        tracking = ConsoleDragTracking()
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: viewport))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: contentHeight))
        scroll.documentView = document
        anchor = ConsoleEdgeAnchorView(dragTracking: tracking)
        document.addSubview(anchor)
        anchor.bindIfNeeded()
        setViewport(viewport, offset: offset)
        anchor.followViewport()
    }

    var offset: CGFloat { scroll.contentView.bounds.origin.y }

    func setViewport(_ height: CGFloat, offset: CGFloat? = nil) {
        var bounds = scroll.contentView.bounds
        bounds.size.height = height
        if let offset {
            bounds.origin.y = offset
        }
        scroll.contentView.bounds = bounds
    }
}
