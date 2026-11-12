import AppKit
import Testing
@testable import MarineSimulator

#if DEBUG

@Suite(.serialized)
struct ScrollRuntimeTraceTests {
    @Test @MainActor func theTraceNamesTheScrollViewAndSeparatesTheWriteFromWhatFollows() {
        let trace = ScrollRuntimeTrace()
        defer { trace.resetForTest() }
        trace.noteSelection("diagnostics")
        trace.start()

        let diagnostics = TraceScrollRig(trace: trace, page: .diagnostics, slot: "primary", contentHeight: 2000, viewport: 500)
        diagnostics.userScroll(to: 640)
        let simulation = TraceScrollRig(trace: trace, page: .simulation, slot: "preview", contentHeight: 1800, viewport: 400)
        simulation.userScroll(to: 220)

        let stuck = TraceScrollRig(
            trace: trace,
            page: .diagnostics,
            slot: "form",
            contentHeight: 2000,
            viewport: 500,
            clip: StuckOriginClipView()
        )
        stuck.session.remember(480, page: .diagnostics, slot: "form")
        let restore = TraceScrollRig(
            trace: trace,
            page: .diagnostics,
            slot: "form",
            session: stuck.session,
            contentHeight: 2000,
            viewport: 500,
            clip: StuckOriginClipView()
        )
        _ = restore

        diagnostics.anchor.noteEnvironmentIdentity(page: .simulation, slot: "primary")
        diagnostics.userScroll(to: 50)

        let text = trace.text()
        #expect(text.contains("frozen=diagnostics"))
        #expect(text.contains("frozen=simulation"))
        #expect(text.contains("slot=primary"))
        #expect(text.contains("slot=preview"))
        #expect(text.contains("scroll=\(ScrollRuntimeTrace.identity(diagnostics.scroll))"))
        #expect(text.contains("scroll=\(ScrollRuntimeTrace.identity(simulation.scroll))"))
        #expect(ScrollRuntimeTrace.identity(diagnostics.scroll) != ScrollRuntimeTrace.identity(simulation.scroll))
        #expect(text.contains("kind=userScroll"))
        #expect(text.contains("origin=640.000"))
        #expect(text.contains("origin=220.000"))
        #expect(text.contains("kind=programmaticWrite"))
        #expect(text.contains("requested=480.000"))
        #expect(text.contains("observed=12.000"))
        #expect(text.contains("kind=lateCallback"))
        #expect(text.contains("kind=anchorRetired"))

        let count = trace.count
        trace.stop()
        diagnostics.userScroll(to: 700)
        #expect(trace.count == count + 1)
        #expect(trace.text().contains("kind=captureStopped"))
        #expect(!trace.text().contains("origin=700.000"))
    }
}

@MainActor
private final class TraceScrollRig {
    let session: PagePresentationSession
    let scroll: NSScrollView
    let anchor: ConsoleEdgeAnchorView

    init(
        trace: ScrollRuntimeTrace,
        page: SidebarItem,
        slot: String,
        session: PagePresentationSession? = nil,
        contentHeight: CGFloat,
        viewport: CGFloat,
        clip: NSClipView? = nil
    ) {
        self.session = session ?? PagePresentationSession()
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: viewport))
        if let clip {
            scroll.contentView = clip
        }
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: contentHeight))
        scroll.documentView = document
        anchor = ConsoleEdgeAnchorView(
            dragTracking: ConsoleDragTracking(),
            presentation: self.session,
            page: page,
            slot: slot
        )
        anchor.scrollTrace = trace
        document.addSubview(anchor)
        anchor.bindIfNeeded()
        var bounds = scroll.contentView.bounds
        bounds.size.height = viewport
        bounds.origin.y = 0
        scroll.contentView.bounds = bounds
        anchor.followViewport()
    }

    func userScroll(to y: CGFloat) {
        var bounds = scroll.contentView.bounds
        bounds.origin.y = y
        scroll.contentView.bounds = bounds
        anchor.followViewport()
    }
}

private final class StuckOriginClipView: NSClipView {
    override func scroll(to newOrigin: NSPoint) {
        var origin = bounds.origin
        origin.y = 12
        setBoundsOrigin(origin)
    }
}

#else

@Suite struct ScrollRuntimeTraceTests {
    @Test func theReleaseBuildOmitsTheScrollTrace() {
        #expect(Bool(true))
    }
}

#endif
