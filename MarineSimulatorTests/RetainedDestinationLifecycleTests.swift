import AppKit
import MapKit
import QuartzCore
import SwiftUI
import Testing
@testable import MarineSimulator

@Suite(.serialized)
@MainActor
struct RetainedDestinationLifecycleTests {

    @Test
    func onlyApprovedLifecycleClassesStayMounted() {
        let detail = CGSize(width: 960, height: 640)
        let forms: [SidebarItem] = [.connection, .simulation]
        for page in forms {
            #expect(page.lifecycle == .retainedForm)
            #expect(page.retainsDestinationTree)
            #expect(page.placesConsoleInTheShell)
            #expect(page.retainedDashboardSize(fitting: detail) == detail)
        }
        #expect(SidebarItem.boat.lifecycle == .retainedSessionView)
        #expect(SidebarItem.boat.retainsDestinationTree)
        #expect(SidebarItem.boat.placesConsoleInTheShell)
        #expect(SidebarItem.boat.retainedDashboardSize(fitting: detail) == detail)

        #expect(SidebarItem.dashboard.lifecycle == .retainedDashboardMap)
        #expect(SidebarItem.dashboard.retainsDestinationTree == false)
        #expect(SidebarItem.dashboard.placesConsoleInTheShell == false)
        #expect(SidebarItem.dashboard.retainedDashboardSize(fitting: detail) == detail)

        #expect(SidebarItem.gps.lifecycle == .retainedMapResource)
        #expect(SidebarItem.gps.retainsDestinationTree == false)
        #expect(SidebarItem.gps.placesConsoleInTheShell)
        #expect(SidebarItem.gps.retainedDashboardSize(fitting: detail) == detail)

        let ephemeral: [SidebarItem] = [.diagnostics, .wind, .hydro, .compass, .manual]
        for page in ephemeral {
            #expect(page.lifecycle == .ephemeral)
            #expect(page.retainsDestinationTree == false)
            #expect(page.placesConsoleInTheShell)
            #expect(page.retainedDashboardSize(fitting: detail) == detail)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func warmedConnectionAndSimulationStayMountedAndOtherPagesLeave() throws {
        let harness = try DestinationHarness(selection: .connection)
        defer { harness.close() }

        let connectionReady = harness.waitUntil {
            harness.marker(.connection)?.enclosingScrollView?.bounds.width ?? 0 > 300
                && harness.consoleHosts().count == 1
                && harness.largeMapViews().isEmpty
        }
        try #require(connectionReady, "connection did not lay out: \(harness.describe())")

        let connectionMarker = try #require(harness.marker(.connection))
        let connectionScroll = try #require(connectionMarker.enclosingScrollView)
        let connectionHost = try #require(harness.destinationHost(.connection))
        let connectionRoot = connectionHost.root
        let dashboardMap = try #require(harness.mapHosts().first)
        let shellConsole = try #require(harness.consoleHosts().first)
        #expect(dashboardMap.isHiddenOrHasHiddenAncestor)
        #expect(dashboardMap.bounds.width > 400)
        #expect(harness.boundAnchors(in: connectionScroll).count == 1)

        harness.select(.simulation)
        let simulationReady = harness.waitUntil {
            guard let simulationScroll = harness.marker(.simulation)?.enclosingScrollView else { return false }
            return simulationScroll.bounds.width > 300
                && simulationScroll.bounds.height > 200
                && harness.isParked(connectionScroll)
                && harness.marker(.connection) === connectionMarker
        }
        try #require(simulationReady, "simulation did not keep connection mounted: \(harness.describe())")
        let simulationMarker = try #require(harness.marker(.simulation))
        let simulationScroll = try #require(simulationMarker.enclosingScrollView)
        #expect(harness.consoleHosts().count == 1)
        #expect(harness.consoleHosts().first === shellConsole)
        #expect(harness.boundAnchors(in: connectionScroll).isEmpty)
        #expect(harness.boundAnchors(in: simulationScroll).count == 1)
        #expect(harness.destinationHost(.connection) === connectionHost)
        #expect(connectionHost.root === connectionRoot)
        #expect(harness.hit(atCenterOf: harness.host)?.isDescendant(of: connectionScroll) != true)
        #expect(connectionHost.hitTest(NSPoint(x: 8, y: 8)) == nil)
        #expect(harness.textFields(in: connectionScroll).allSatisfy(harness.isHiddenFromAccessibility))
        #expect(harness.mapHosts().count == 1)
        #expect(harness.mapHosts().first === dashboardMap)
        #expect(harness.largeMapViews().isEmpty)

        harness.select(.diagnostics)
        let diagnosticsReady = harness.waitUntil {
            harness.showsDiagnosticsPage()
                && harness.isParked(connectionScroll)
                && harness.isParked(simulationScroll)
                && harness.boundAnchors(in: connectionScroll).isEmpty
                && harness.boundAnchors(in: simulationScroll).isEmpty
                && harness.markers().count == 2
                && harness.looseMapViews().isEmpty
        }
        try #require(diagnosticsReady, "diagnostics did not replace the retained pages in layout: \(harness.describe())")
        #expect(harness.marker(.connection) === connectionMarker)
        #expect(harness.marker(.simulation) === simulationMarker)
        #expect(harness.destinationHost(.connection) === connectionHost)
        #expect(connectionHost.root === connectionRoot)
        #expect(connectionMarker.enclosingScrollView === connectionScroll)
        #expect(simulationMarker.enclosingScrollView === simulationScroll)
        #expect(harness.destinationHost(.diagnostics) == nil)
        #expect(harness.destinationHost(.manual) == nil)
        #expect(harness.destinationHost(.boat) == nil)
        #expect(harness.consoleHosts().count == 1)
        #expect(harness.consoleHosts().first === shellConsole)

        harness.select(.wind)
        let windReady = harness.waitUntil {
            harness.showsDiagnosticsPage() == false
                && harness.showsWindPage()
                && harness.marker(.connection) === connectionMarker
                && harness.markers().count == 2
                && harness.looseMapViews().isEmpty
        }
        try #require(windReady, "wind stayed mounted or cloned a retained tree: \(harness.describe())")
        #expect(harness.consoleHosts().count == 1)
        #expect(harness.consoleHosts().first === shellConsole)
        #expect(harness.mapHosts().first === dashboardMap)

        harness.select(.gps)
        let gpsReady = harness.waitUntil {
            harness.showsWindPage() == false
                && harness.looseMapViews().count == 1
                && harness.markers().count == 2
                && harness.mapHosts().first === dashboardMap
                && harness.isParked(connectionScroll)
                && harness.isParked(simulationScroll)
        }
        try #require(gpsReady, "gps did not release the sentence page: \(harness.describe())")
        #expect(harness.destinationHost(.gps) == nil)
        #expect(harness.consoleHosts().count == 1)
        #expect(harness.consoleHosts().first === shellConsole)

        harness.select(.connection)
        let connectionReturned = harness.waitUntil {
            connectionScroll.bounds.width > 300
                && connectionScroll.bounds.height > 200
                && harness.isParked(simulationScroll)
                && harness.showsDiagnosticsPage() == false
                && harness.showsWindPage() == false
                && harness.looseMapViews().isEmpty
                && harness.boundAnchors(in: connectionScroll).count == 1
                && harness.boundAnchors(in: simulationScroll).isEmpty
        }
        try #require(connectionReturned, "returning to connection rebuilt or uncovered the wrong page: \(harness.describe())")
        #expect(harness.marker(.connection) === connectionMarker)
        #expect(harness.consoleHosts().count == 1)
        #expect(harness.consoleHosts().first === shellConsole)

        harness.select(.dashboard)
        let dashboardReady = harness.waitUntil {
            !dashboardMap.isHiddenOrHasHiddenAncestor
                && dashboardMap.bounds.width > 400
                && dashboardMap.bounds.height > 300
                && harness.isParked(connectionScroll)
                && harness.isParked(simulationScroll)
                && harness.consoleHosts().count == 1
                && harness.largeMapViews().count == 1
        }
        try #require(dashboardReady, "dashboard did not take the column back: \(harness.describe())")
        #expect(harness.marker(.connection) === connectionMarker)
        #expect(harness.marker(.simulation) === simulationMarker)
        #expect(harness.mapHosts().count == 1)
        #expect(harness.mapHosts().first === dashboardMap)
        #expect(harness.boundAnchors(in: connectionScroll).isEmpty)
        #expect(harness.boundAnchors(in: simulationScroll).isEmpty)

        harness.select(.simulation)
        let simulationReturned = harness.waitUntil {
            simulationScroll.bounds.width > 300
                && simulationScroll.bounds.height > 200
                && harness.isParked(connectionScroll)
                && dashboardMap.isHiddenOrHasHiddenAncestor
                && harness.consoleHosts().count == 1
                && harness.largeMapViews().isEmpty
                && harness.boundAnchors(in: simulationScroll).count == 1
        }
        try #require(simulationReturned, "simulation was rebuilt after dashboard: \(harness.describe())")
        #expect(harness.marker(.simulation) === simulationMarker)
        #expect(simulationMarker.enclosingScrollView === simulationScroll)
        #expect(harness.marker(.connection) === connectionMarker)
    }

    @Test(.timeLimit(.minutes(2)))
    func anInactiveRetainedPageDoesNotCaptureTheActivePageScroll() throws {
        let harness = try DestinationHarness(selection: .connection, consoleHeight: 280)
        defer { harness.close() }

        let ready = harness.waitUntil {
            guard let scroll = harness.marker(.connection)?.enclosingScrollView else { return false }
            let room = (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height
            return scroll.bounds.width > 300 && room > 80 && harness.boundAnchors(in: scroll).count == 1
        }
        try #require(ready, "connection did not open a scrolling page: \(harness.describe())")
        let connectionScroll = try #require(harness.marker(.connection)?.enclosingScrollView)
        let limits = ConsoleScrollLimits.reading(
            connectionScroll.contentView,
            viewportHeight: connectionScroll.contentView.bounds.height
        )
        let target = min(limits.maximum - 8, max(limits.minimum + 36, 64))
        try #require(target > limits.minimum + 4 && target < limits.maximum - 4)

        harness.scroll(connectionScroll, to: target)
        let held = harness.waitUntil(timeout: 2) {
            abs(connectionScroll.contentView.bounds.origin.y - target) < 2
        }
        try #require(held, "connection did not keep \(target), origin \(connectionScroll.contentView.bounds.origin.y)")

        harness.select(.simulation)
        let hidden = harness.waitUntil {
            harness.isParked(connectionScroll)
                && harness.boundAnchors(in: connectionScroll).isEmpty
                && (harness.marker(.simulation)?.enclosingScrollView?.bounds.width ?? 0) > 300
        }
        try #require(hidden, "simulation did not unbind the connection anchor: \(harness.describe())")
        let simulationScroll = try #require(harness.marker(.simulation)?.enclosingScrollView)
        let simulationAnchors = harness.boundAnchors(in: simulationScroll)
        #expect(simulationAnchors.count == 1)
        if let anchor = simulationAnchors.first, simulationScroll.documentView?.bounds.height ?? 0 > simulationScroll.contentView.bounds.height + 40 {
            let before = connectionScroll.contentView.bounds.origin.y
            anchor.followViewport()
            simulationScroll.contentView.scroll(to: NSPoint(x: 0, y: 24))
            anchor.followViewport()
            #expect(abs(connectionScroll.contentView.bounds.origin.y - before) < 1)
        }

        harness.select(.connection)
        let restored = harness.waitUntil {
            connectionScroll.bounds.width > 300
                && abs(connectionScroll.contentView.bounds.origin.y - target) < 2
                && harness.marker(.connection)?.enclosingScrollView === connectionScroll
                && harness.boundAnchors(in: simulationScroll).isEmpty
        }
        try #require(
            restored,
            "connection returned at \(connectionScroll.contentView.bounds.origin.y), expected \(target): \(harness.describe())"
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func retainedSimulationScrollPreservedAcrossDiagnosticsAtMidAndZero() throws {
        ScrollRuntimeTrace.shared.start()
        defer { ScrollRuntimeTrace.shared.resetForTest() }
        let harness = try DestinationHarness(selection: .simulation, consoleHeight: 200)
        defer { harness.close() }

        let simReady = harness.waitUntil {
            guard let scroll = harness.marker(.simulation)?.enclosingScrollView else { return false }
            let room = (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height
            return scroll.bounds.width > 300 && room > 120 && harness.boundAnchors(in: scroll).count == 1
        }
        try #require(simReady, "simulation not ready")
        let simScroll = try #require(harness.marker(.simulation)?.enclosingScrollView)
        let insets = simScroll.contentView.contentInsets
        let docHeight = simScroll.documentView?.bounds.height ?? 0
        let viewHeight = simScroll.contentView.bounds.height
        let mid: CGFloat = 150
        harness.scroll(simScroll, to: mid)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: simScroll)
        #expect(harness.waitUntil { abs(simScroll.contentView.bounds.origin.y - mid) < 2 })

        harness.select(.diagnostics)
        let diagReady = harness.waitUntil {
            harness.showsDiagnosticsPage() && harness.isParked(simScroll)
        }
        try #require(diagReady)

        harness.select(.simulation)
        let backMid = harness.waitUntil {
            simScroll.bounds.width > 300 && harness.boundAnchors(in: simScroll).count == 1
        }
        try #require(backMid)
        // Wait until async restore settle expires
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let afterMid = simScroll.contentView.bounds.origin.y
        try #require(abs(afterMid - mid) < 2, "mid shifted to \(afterMid) insets=(\(insets.top),\(insets.bottom)) doc=\(docHeight) view=\(viewHeight)")

        // Now simulate real trackpad scroll back to minimum (didLiveScroll fires after origin change)
        let minBefore = ConsoleScrollLimits.reading(simScroll.contentView, viewportHeight: simScroll.contentView.bounds.height).minimum
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: simScroll)
        harness.scroll(simScroll, to: minBefore)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: simScroll)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: simScroll)
        let reachedZero = harness.waitUntil { abs(simScroll.contentView.bounds.origin.y - minBefore) < 2 }
        try #require(reachedZero, "scroll to min=\(minBefore) stayed at \(simScroll.contentView.bounds.origin.y): trace=\n\(ScrollRuntimeTrace.shared.text())")

        harness.select(.diagnostics)
        try #require(harness.waitUntil { harness.showsDiagnosticsPage() && harness.isParked(simScroll) })

        harness.select(.simulation)
        try #require(harness.waitUntil { simScroll.bounds.width > 300 && harness.boundAnchors(in: simScroll).count == 1 })
        let deadline2 = Date().addingTimeInterval(0.2)
        while Date() < deadline2 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let afterZero = simScroll.contentView.bounds.origin.y
        try #require(abs(afterZero - minBefore) < 2, "min=\(minBefore) shifted to \(afterZero) insets=(\(insets.top),\(insets.bottom)): trace=\n\(ScrollRuntimeTrace.shared.text())")
    }

    @Test(.timeLimit(.minutes(2)))
    func retainedSimulationScrollPreservedAcrossConnectionAtMidAndNearBottom() throws {
        ScrollRuntimeTrace.shared.start()
        defer { ScrollRuntimeTrace.shared.resetForTest() }
        let harness = try DestinationHarness(selection: .simulation, consoleHeight: 200)
        defer { harness.close() }

        let simReady = harness.waitUntil {
            guard let scroll = harness.marker(.simulation)?.enclosingScrollView else { return false }
            let room = (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height
            return scroll.bounds.width > 300 && room > 200 && harness.boundAnchors(in: scroll).count == 1
        }
        try #require(simReady, "simulation not ready")
        let simScroll = try #require(harness.marker(.simulation)?.enclosingScrollView)
        let limits = ConsoleScrollLimits.reading(simScroll.contentView, viewportHeight: simScroll.contentView.bounds.height)
        let mid = (limits.minimum + limits.maximum) * 0.5
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: simScroll)
        harness.scroll(simScroll, to: mid)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: simScroll)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: simScroll)
        #expect(harness.waitUntil { abs(simScroll.contentView.bounds.origin.y - mid) < 2 })

        harness.select(.connection)
        let connReady = harness.waitUntil {
            guard let connScroll = harness.marker(.connection)?.enclosingScrollView else { return false }
            return connScroll.bounds.width > 300 && harness.isParked(simScroll)
        }
        try #require(connReady)

        harness.select(.simulation)
        try #require(harness.waitUntil { simScroll.bounds.width > 300 && harness.boundAnchors(in: simScroll).count == 1 })
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let afterMid = simScroll.contentView.bounds.origin.y
        try #require(abs(afterMid - mid) < 2, "mid=\(mid) shifted to \(afterMid): trace=\n\(ScrollRuntimeTrace.shared.text())")

        // Also test near bottom (maximum)
        let maxPos = ConsoleScrollLimits.reading(simScroll.contentView, viewportHeight: simScroll.contentView.bounds.height).maximum
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: simScroll)
        harness.scroll(simScroll, to: maxPos)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: simScroll)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: simScroll)
        #expect(harness.waitUntil { abs(simScroll.contentView.bounds.origin.y - maxPos) < 2 })

        harness.select(.connection)
        try #require(harness.waitUntil {
            guard let connScroll = harness.marker(.connection)?.enclosingScrollView else { return false }
            return connScroll.bounds.width > 300 && harness.isParked(simScroll)
        })

        harness.select(.simulation)
        try #require(harness.waitUntil { simScroll.bounds.width > 300 && harness.boundAnchors(in: simScroll).count == 1 })
        let deadline2 = Date().addingTimeInterval(0.6)
        while Date() < deadline2 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let afterMax = simScroll.contentView.bounds.origin.y
        try #require(abs(afterMax - maxPos) < 2, "max=\(maxPos) shifted to \(afterMax): trace=\n\(ScrollRuntimeTrace.shared.text())")
    }

    /// The active page is in the key-view loop. Parking hides that host, so traversal skips it
    /// without rewriting each field's own focus policy.
    @Test(.timeLimit(.minutes(2)))
    func anActiveConnectionFieldResignsWhenSimulationIsSelected() throws {
        let harness = try DestinationHarness(selection: .connection)
        defer { harness.close() }

        let ready = harness.waitUntil {
            guard let scroll = harness.marker(.connection)?.enclosingScrollView else { return false }
            return scroll.bounds.width > 300
                && scroll.bounds.height > 200
                && harness.editableField(in: scroll) != nil
                && harness.boundAnchors(in: scroll).count == 1
        }
        try #require(ready, "connection did not present an editable field: \(harness.describe())")

        let connectionMarker = try #require(harness.marker(.connection))
        let connectionScroll = try #require(connectionMarker.enclosingScrollView)
        let connectionHost = try #require(harness.destinationHost(.connection))
        let field = try #require(harness.editableField(in: connectionScroll))
        let policy = FieldPolicy(field)
        let activeLoop = harness.keyViewLoop()
        #expect(activeLoop.contains { $0 === field })
        #expect(field.canBecomeKeyView)
        let focused = harness.focus(field)
        try #require(focused, "connection field refused first responder while the page was active")
        let editor = try #require(field.currentEditor(), "the active field did not open an editor")
        #expect(harness.responderIsInside(connectionScroll))
        #expect(editor === harness.window.firstResponder || field === harness.window.firstResponder)
        #expect(policy.matches(field))

        harness.select(.simulation)
        let resigned = harness.waitUntil {
            guard let simulationScroll = harness.marker(.simulation)?.enclosingScrollView else { return false }
            return field.currentEditor() == nil
                && harness.responderIsInside(connectionScroll) == false
                && harness.isParked(connectionScroll)
                && connectionHost.isHidden
                && simulationScroll.bounds.width > 300
                && simulationScroll.bounds.height > 200
                && harness.boundAnchors(in: connectionScroll).isEmpty
                && harness.boundAnchors(in: simulationScroll).count == 1
                && policy.matches(field)
        }
        try #require(
            resigned,
            "connection kept focus or its anchor after Simulation: refuses=\(field.refusesFirstResponder) inside=\(harness.responderIsInside(connectionScroll)) \(harness.describe())"
        )
        let parkedLoop = harness.keyViewLoop()
        #expect(parkedLoop.contains { $0 === field } == false)
        #expect(parkedLoop.allSatisfy { $0.isDescendant(of: connectionHost) == false })
        #expect(field.canBecomeKeyView == false)
        #expect(field.isHiddenOrHasHiddenAncestor)
        _ = harness.window.makeFirstResponder(field)
        #expect(field.currentEditor() == nil)
        #expect(harness.window.firstResponder !== field)
        #expect(harness.responderIsInside(connectionScroll) == false)
        #expect(connectionHost.hitTest(NSPoint(x: 8, y: 8)) == nil)
        #expect(harness.hit(atCenterOf: harness.host)?.isDescendant(of: connectionScroll) != true)
        #expect(harness.isHiddenFromAccessibility(field))
        #expect(policy.matches(field))

        let simulationScroll = try #require(harness.marker(.simulation)?.enclosingScrollView)
        harness.select(.manual)
        let manual = harness.waitUntil {
            !harness.manualSearchFields().isEmpty
                && harness.isParked(connectionScroll)
                && harness.isParked(simulationScroll)
                && field.currentEditor() == nil
                && harness.responderIsInside(connectionScroll) == false
                && harness.boundAnchors(in: connectionScroll).isEmpty
                && harness.boundAnchors(in: simulationScroll).isEmpty
                && policy.matches(field)
        }
        try #require(manual, "manual did not leave the connection field parked: \(harness.describe())")
        let manualField = try #require(harness.manualSearchFields().first as? NSTextField)
        #expect(harness.keyViewLoop().contains { $0 === manualField })
        #expect(harness.keyViewLoop().contains { $0 === field } == false)
        _ = harness.window.makeFirstResponder(field)
        #expect(field.currentEditor() == nil)
        #expect(harness.window.firstResponder !== field)
        #expect(harness.responderIsInside(connectionScroll) == false)
        #expect(harness.textFields(in: connectionScroll).contains { $0 === field })
        #expect(harness.isHiddenFromAccessibility(field))
        #expect(policy.matches(field))

        harness.select(.connection)
        let restored = harness.waitUntil {
            connectionScroll.bounds.width > 300
                && connectionScroll.bounds.height > 200
                && connectionHost.isHidden == false
                && harness.marker(.connection)?.enclosingScrollView === connectionScroll
                && harness.textFields(in: connectionScroll).contains { $0 === field }
                && policy.matches(field)
                && field.canBecomeKeyView
                && harness.focus(field)
        }
        try #require(restored, "connection did not return to the key-view loop: \(harness.describe())")
        #expect(field.currentEditor() != nil)
        #expect(harness.keyViewLoop().contains { $0 === field })
        #expect(policy.matches(field))
    }

    /// Selection updates the stable host. It does not evaluate Connection or Simulation again.
    @Test(.timeLimit(.minutes(2)))
    func activityTogglesDoNotRebuildTheRetainedForms() throws {
        let harness = try DestinationHarness(selection: .connection)
        defer { harness.close() }

        let connectionReady = harness.waitUntil {
            guard let scroll = harness.marker(.connection)?.enclosingScrollView else { return false }
            return scroll.bounds.width > 300
                && scroll.bounds.height > 200
                && harness.destinationHost(.connection)?.root.frame.width ?? 0 > 300
        }
        try #require(connectionReady, "connection host did not lay out: \(harness.describe())")
        let connectionHost = try #require(harness.destinationHost(.connection))
        let connectionRoot = connectionHost.root
        let connectionScroll = try #require(harness.marker(.connection)?.enclosingScrollView)
        let field = try #require(harness.editableField(in: connectionScroll))

        harness.select(.simulation)
        let simulationReady = harness.waitUntil {
            guard let scroll = harness.marker(.simulation)?.enclosingScrollView else { return false }
            return scroll.bounds.width > 300
                && scroll.bounds.height > 200
                && harness.isParked(connectionScroll)
                && harness.destinationHost(.simulation)?.isPageActive == true
        }
        try #require(simulationReady, "simulation host did not lay out: \(harness.describe())")
        let simulationHost = try #require(harness.destinationHost(.simulation))
        let simulationRoot = simulationHost.root
        let simulationScroll = try #require(harness.marker(.simulation)?.enclosingScrollView)

        #if DEBUG
        let connectionBodies = RetainedDestinationBodyProbe.connectionEvaluations
        let simulationBodies = RetainedDestinationBodyProbe.simulationEvaluations
        try #require(connectionBodies > 0 && simulationBodies > 0)
        #endif

        harness.select(.connection)
        harness.select(.simulation)
        harness.select(.manual)
        let manualShown = harness.waitUntil {
            harness.destinationHost(.manual) == nil
                && harness.manualSearchFields().isEmpty == false
                && harness.isParked(connectionScroll)
                && harness.isParked(simulationScroll)
        }
        try #require(manualShown, "manual did not park the retained forms: \(harness.describe())")
        #if DEBUG
        #expect(RetainedDestinationBodyProbe.connectionEvaluations == connectionBodies)
        #expect(RetainedDestinationBodyProbe.simulationEvaluations == simulationBodies)
        #endif
        harness.select(.connection)
        let settled = harness.waitUntil {
            connectionScroll.bounds.width > 300
                && harness.destinationHost(.connection)?.isPageActive == true
                && harness.isParked(simulationScroll)
                && harness.destinationHost(.manual) == nil
                && harness.manualSearchFields().isEmpty
                && harness.boundAnchors(in: connectionScroll).count == 1
                && harness.boundAnchors(in: simulationScroll).isEmpty
        }
        try #require(settled, "activity round trip did not settle: \(harness.describe())")
        #expect(harness.destinationHost(.connection) === connectionHost)
        #expect(connectionHost.root === connectionRoot)
        #expect(harness.destinationHost(.simulation) === simulationHost)
        #expect(simulationHost.root === simulationRoot)
        #expect(harness.marker(.connection)?.enclosingScrollView === connectionScroll)
        #expect(harness.marker(.simulation)?.enclosingScrollView === simulationScroll)
        #expect(harness.textFields(in: connectionScroll).contains { $0 === field })
        #if DEBUG
        #expect(RetainedDestinationBodyProbe.connectionEvaluations == connectionBodies)
        #expect(RetainedDestinationBodyProbe.simulationEvaluations == simulationBodies)
        #endif
    }

    /// Switching warmed pages must not run the retained hosting view's layout.
    /// A real host-size change still reaches that layout through the normal cycle.
    @Test(.timeLimit(.minutes(2)))
    func ordinaryActivationDoesNotLayOutTheRetainedRoot() throws {
        let harness = try DestinationHarness(selection: .connection)
        defer { harness.close() }

        harness.select(.simulation)
        let warmed = harness.waitUntil {
            guard let connection = harness.destinationHost(.connection),
                  let simulation = harness.destinationHost(.simulation),
                  let connectionScroll = harness.marker(.connection)?.enclosingScrollView else { return false }
            return connection.root.frame.width > 300
                && simulation.root.frame.width > 300
                && connection.root.performedLayoutCount > 0
                && simulation.root.performedLayoutCount > 0
                && harness.isParked(connectionScroll)
                && simulation.isPageActive
        }
        try #require(warmed, "retained pages did not finish their first layout: \(harness.describe())")

        let connectionHost = try #require(harness.destinationHost(.connection))
        let simulationHost = try #require(harness.destinationHost(.simulation))
        // The warmup activation can still have work queued. Drain one run-loop turn before the baseline.
        var baselinePassed = false
        let baselineTurn = harness.waitUntil {
            if !baselinePassed {
                baselinePassed = true
                return false
            }
            return simulationHost.isPageActive && connectionHost.isPageActive == false
        }
        try #require(
            baselineTurn,
            "the warmup activation did not reach the next run-loop turn: simulationActive=\(simulationHost.isPageActive) connectionActive=\(connectionHost.isPageActive)"
        )

        let connectionLayouts = connectionHost.root.performedLayoutCount
        let simulationLayouts = simulationHost.root.performedLayoutCount
        let connectionSize = connectionHost.root.frame.size
        let simulationSize = simulationHost.root.frame.size
        #if DEBUG
        let connectionBodies = RetainedDestinationBodyProbe.connectionEvaluations
        let simulationBodies = RetainedDestinationBodyProbe.simulationEvaluations
        #endif

        for item in [SidebarItem.connection, .simulation, .connection] {
            harness.select(item)
            var passedFirstCheck = false
            let settled = harness.waitUntil {
                // The first check fails so waitUntil advances one main run-loop turn before success.
                if !passedFirstCheck {
                    passedFirstCheck = true
                    return false
                }
                guard let connectionScroll = harness.marker(.connection)?.enclosingScrollView,
                      let simulationScroll = harness.marker(.simulation)?.enclosingScrollView else { return false }
                switch item {
                case .connection:
                    return connectionHost.isPageActive
                        && connectionScroll.bounds.width > 300
                        && harness.isParked(simulationScroll)
                case .simulation:
                    return simulationHost.isPageActive
                        && simulationScroll.bounds.width > 300
                        && harness.isParked(connectionScroll)
                default:
                    return false
                }
            }
            try #require(settled, "\(item.rawValue) did not settle on its own turn: \(harness.describe())")
            try #require(
                connectionHost.root.performedLayoutCount == connectionLayouts
                    && simulationHost.root.performedLayoutCount == simulationLayouts
                    && connectionHost.root.frame.size == connectionSize
                    && simulationHost.root.frame.size == simulationSize,
                "\(item.rawValue) laid out a retained root: connection \(connectionLayouts)->\(connectionHost.root.performedLayoutCount) \(connectionSize) simulation \(simulationLayouts)->\(simulationHost.root.performedLayoutCount) \(simulationSize)"
            )
            #if DEBUG
            #expect(RetainedDestinationBodyProbe.connectionEvaluations == connectionBodies)
            #expect(RetainedDestinationBodyProbe.simulationEvaluations == simulationBodies)
            #endif
        }

        harness.window.setContentSize(NSSize(width: 1480, height: 980))
        let resized = harness.waitUntil {
            let hostSize = connectionHost.bounds.size
            return hostSize.width > connectionSize.width + 40
                && abs(connectionHost.root.frame.width - hostSize.width) < 1
                && abs(connectionHost.root.frame.height - hostSize.height) < 1
                && connectionHost.root.performedLayoutCount > connectionLayouts
                && simulationHost.root.performedLayoutCount == simulationLayouts
                && simulationHost.root.frame.size == simulationSize
        }
        try #require(
            resized,
            "a real size change did not lay out the active root: host=\(connectionHost.bounds.size) root=\(connectionHost.root.frame.size) layouts=\(connectionHost.root.performedLayoutCount) parkedRoot=\(simulationHost.root.frame.size) parkedLayouts=\(simulationHost.root.performedLayoutCount)"
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func boatCreatesOnceAndManualLeaves() throws {
        let harness = try DestinationHarness(selection: .boat)
        defer { harness.close() }

        let boatReady = harness.waitUntil {
            guard let boatHost = harness.destinationHost(.boat) else { return false }
            return harness.sessionMarker()?.session != nil
                && boatHost.root.frame.width > 300
                && harness.tables(in: boatHost).isEmpty == false
                && harness.scrollViews(in: boatHost).count >= 2
                && harness.consoleHosts().count == 1
                && harness.largeMapViews().isEmpty
                && harness.destinationHost(.manual) == nil
        }
        try #require(boatReady, "boat did not keep one session root: \(harness.describe())")
        let boatHost = try #require(harness.destinationHost(.boat))
        let boatRoot = boatHost.root
        let boatMarker = try #require(harness.marker(.boat))
        let sessionMarker = try #require(harness.sessionMarker())
        let session = try #require(sessionMarker.session)
        let libraryTable = try #require(harness.tables(in: boatHost).first)
        let boatScrolls = Set(harness.scrollViews(in: boatHost).map(ObjectIdentifier.init))
        let dashboardMap = try #require(harness.mapHosts().first)
        #if DEBUG
        let boatBodies = RetainedDestinationBodyProbe.boatEvaluations
        try #require(boatBodies > 0)
        #endif

        harness.select(.manual)
        let manualShown = harness.waitUntil {
            harness.manualSearchFields().isEmpty == false
                && harness.destinationHost(.manual) == nil
                && harness.isHostParked(.boat)
                && boatHost.root === boatRoot
                && harness.consoleHosts().count == 1
        }
        try #require(manualShown, "manual stayed mounted: \(harness.describe())")

        harness.select(.dashboard)
        let dashboardReady = harness.waitUntil {
            !dashboardMap.isHiddenOrHasHiddenAncestor
                && dashboardMap.bounds.width > 400
                && harness.isHostParked(.boat)
                && harness.destinationHost(.manual) == nil
                && harness.manualSearchFields().isEmpty
                && harness.consoleHosts().count == 1
                && harness.largeMapViews().count == 1
                && harness.mapHosts().first === dashboardMap
        }
        try #require(dashboardReady, "dashboard did not keep its map: \(harness.describe())")

        harness.select(.diagnostics)
        let diagnosticsReady = harness.waitUntil {
            harness.showsDiagnosticsPage()
                && dashboardMap.isHiddenOrHasHiddenAncestor
                && harness.isHostParked(.boat)
                && harness.destinationHost(.manual) == nil
                && harness.looseMapViews().isEmpty
                && harness.consoleHosts().count == 1
        }
        try #require(diagnosticsReady, "diagnostics did not stay ephemeral: \(harness.describe())")

        harness.select(.wind)
        let windReady = harness.waitUntil {
            harness.showsDiagnosticsPage() == false
                && harness.showsWindPage()
                && harness.destinationHost(.boat) === boatHost
                && harness.destinationHost(.manual) == nil
                && harness.looseMapViews().isEmpty
        }
        try #require(windReady, "wind did not release diagnostics: \(harness.describe())")

        harness.select(.gps)
        let gpsReady = harness.waitUntil {
            harness.showsWindPage() == false
                && harness.looseMapViews().count == 1
                && harness.mapHosts().count == 1
                && harness.mapHosts().first === dashboardMap
                && harness.destinationHost(.gps) == nil
                && boatHost.root === boatRoot
        }
        try #require(gpsReady, "gps kept a page host or a second dashboard map: \(harness.describe())")

        harness.select(.boat)
        let boatReturned = harness.waitUntil {
            boatHost.isPageActive
                && harness.destinationHost(.manual) == nil
                && harness.manualSearchFields().isEmpty
                && harness.sessionMarker() === sessionMarker
                && harness.sessionMarker()?.session === session
                && harness.marker(.boat) === boatMarker
                && harness.tables(in: boatHost).first === libraryTable
                && Set(harness.scrollViews(in: boatHost).map(ObjectIdentifier.init)) == boatScrolls
                && harness.consoleHosts().count == 1
                && harness.mapHosts().first === dashboardMap
                && harness.looseMapViews().isEmpty
        }
        try #require(boatReturned, "boat session was rebuilt: \(harness.describe())")
        #expect(boatHost.root === boatRoot)
        #expect(harness.destinationHost(.connection) == nil)
        #expect(harness.destinationHost(.simulation) == nil)
        #expect(harness.destinationHost(.diagnostics) == nil)
        #expect(harness.destinationHost(.wind) == nil)
        #expect(harness.destinationHost(.gps) == nil)
        #expect(harness.destinationHost(.manual) == nil)
        #if DEBUG
        #expect(RetainedDestinationBodyProbe.boatEvaluations == boatBodies)
        #endif
    }

    @Test(.timeLimit(.minutes(2)))
    func boatSailEditAutosavesAndSessionSurvivesNavigation() throws {
        let store = CountingVesselProfileStore()
        let harness = try DestinationHarness(selection: .boat, vesselStore: store)
        defer { harness.close() }

        let ready = harness.waitUntil {
            harness.revealBoatEditor()
            guard let boatHost = harness.destinationHost(.boat), boatHost.root.frame.width > 300 else { return false }
            return harness.sessionMarker()?.session?.highlightedID == BuiltInVesselID.extasy
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Mainsail 1" }
        }
        try #require(ready, "boat did not open the active vessel draft: \(harness.describe())")
        let saves = store.saveCount
        try #require(saves > 0, "the library did not seed its store")
        let boatHost = try #require(harness.destinationHost(.boat))
        let sessionMarker = try #require(harness.sessionMarker())
        let session = try #require(sessionMarker.session)

        session.show(BuiltInVesselID.nimana, on: harness.simulator)
        let nimana = harness.waitUntil {
            session.highlightedID == BuiltInVesselID.nimana
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Mainsail 0" && $0.bounds.width > 2 }
        }
        try #require(
            nimana,
            "the retained session did not show Nimana: id=\(session.highlightedID?.uuidString ?? "nil") sail=\(session.buffer.sails.first?.name ?? "nil") \(harness.describe())"
        )
        let draftField = try #require(harness.textFields(in: boatHost).first { $0.stringValue == "Mainsail 0" })
        try #require(harness.replaceText(draftField, with: "Mainsail 0 draft"))
        let drafted = harness.waitUntil {
            session.buffer.sails.contains { $0.name == "Mainsail 0 draft" }
                && draftField.stringValue == "Mainsail 0 draft"
        }
        try #require(drafted, "the sail field did not keep the edited name: \(draftField.stringValue)")
        session.editingSailID = ReferenceSailID.nimanaHeadsail
        let editorMoved = harness.waitUntil {
            session.editingSailID == ReferenceSailID.nimanaHeadsail
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Headsail 0" && $0.bounds.width > 2 }
        }
        try #require(editorMoved, "the sail editor did not move to Headsail 0: \(harness.describe())")
        let editorField = try #require(harness.textFields(in: boatHost).first { $0.stringValue == "Headsail 0" })
        let persistedSail = harness.waitUntil {
            harness.simulator.vessels.first { $0.id == BuiltInVesselID.nimana }?.inventory.first { $0.id == ReferenceSailID.nimanaMainsail }?.name == "Mainsail 0 draft"
                && store.saveCount > saves
        }
        try #require(persistedSail, "the sail edit did not autosave")
        #expect(harness.simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.name == "Extasy")
        #expect(harness.simulator.vessels.first { $0.id == BuiltInVesselID.nimana }?.origin == .builtIn)
        let savesAfterEdit = store.saveCount

        harness.select(.dashboard)
        harness.select(.diagnostics)
        let away = harness.waitUntil {
            harness.showsDiagnosticsPage()
                && harness.isHostParked(.boat)
                && harness.consoleHosts().count == 1
        }
        try #require(away, "diagnostics did not park the boat session: \(harness.describe())")
        harness.select(.manual)
        harness.select(.boat)
        let returned = harness.waitUntil {
            boatHost.isPageActive
                && harness.sessionMarker() === sessionMarker
                && harness.sessionMarker()?.session === session
                && session.highlightedID == BuiltInVesselID.nimana
                && session.editingSailID == ReferenceSailID.nimanaHeadsail
                && session.buffer.sails.contains { $0.name == "Mainsail 0 draft" }
                && editorField.stringValue == "Headsail 0"
                && harness.textFields(in: boatHost).contains { $0 === editorField }
                && harness.destinationHost(.manual) == nil
                && harness.consoleHosts().count == 1
        }
        try #require(returned, "the boat session was replaced: \(harness.describe())")
        #expect(store.saveCount == savesAfterEdit)
        #expect(store.document?.profiles.first { $0.id == BuiltInVesselID.nimana }?.inventory.first { $0.id == ReferenceSailID.nimanaMainsail }?.name == "Mainsail 0 draft")
        #expect(harness.simulator.vessels.first { $0.id == BuiltInVesselID.nimana }?.inventory.first { $0.id == ReferenceSailID.nimanaMainsail }?.name == "Mainsail 0 draft")
        #expect(harness.simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.name == "Extasy")
    }

    @Test(.timeLimit(.minutes(2)))
    func boatNewControlPersistsAnEditableProfileAndAutosavesValidEdits() throws {
        let store = CountingVesselProfileStore()
        let harness = try DestinationHarness(selection: .boat, vesselStore: store)
        defer { harness.close() }

        let ready = harness.waitUntil {
            harness.revealBoatEditor()
            guard let boatHost = harness.destinationHost(.boat), boatHost.isPageActive, boatHost.root.frame.width > 300 else {
                return false
            }
            return harness.sessionMarker()?.session?.highlightedID == BuiltInVesselID.extasy
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Mainsail 1" && $0.isEditable }
        }
        try #require(ready, "boat did not present an editable sail field: \(harness.describe())")
        let boatHost = try #require(harness.destinationHost(.boat))
        let sessionMarker = try #require(harness.sessionMarker())
        let session = try #require(sessionMarker.session)
        #expect(harness.textFields(in: boatHost).contains { $0.stringValue == "Extasy" && $0.isEditable } == false)
        try harness.requireLibraryCommands(in: boatHost, deleteEnabled: false)
        let saves = store.saveCount

        let pressed = harness.pressNewVessel(in: boatHost)
        let created = harness.waitUntil {
            let profile = harness.simulator.vessels.first { $0.name == "Custom Vessel" }
            return profile?.origin == .custom
                && session.highlightedID == profile?.id
                && session.buffer.name == "Custom Vessel"
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Custom Vessel" && $0.isEditable }
                && store.saveCount > saves
        }
        if pressed == false || created == false {
            let report = "pressed=\(pressed) buttons=\(harness.buttonSummary(in: boatHost)) names=\(harness.simulator.vessels.map(\.name).joined(separator: ",")) highlighted=\(session.highlightedID?.uuidString ?? "nil") buffer=\(session.buffer.name) saves=\(store.saveCount)/\(saves) splits=\(harness.splitSummary(in: boatHost)) pane=\(harness.libraryPaneDump(in: boatHost))"
            try? report.write(
                to: URL(fileURLWithPath: "/Users/bacataborisov/Documents/Projects/MarineSimulator/.agent-scratch/boat-new-diagnosis.txt"),
                atomically: true,
                encoding: .utf8
            )
            try #require(pressed && created, "New did not persist an editable profile")
        }
        let createdProfile = try #require(harness.simulator.vessels.first { $0.name == "Custom Vessel" })
        #expect(createdProfile.performance == VesselProfile.Performance.none)
        #expect(harness.simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.name == "Extasy")
        #expect(harness.simulator.selectedVesselID == BuiltInVesselID.extasy)
        try harness.requireLibraryCommands(in: boatHost, deleteEnabled: true)
        let savesAfterCreate = store.saveCount

        let nameField = try #require(harness.textFields(in: boatHost).first { $0.stringValue == "Custom Vessel" && $0.isEditable })
        try #require(harness.replaceText(nameField, with: "Skiff"))
        let renamed = harness.waitUntil {
            session.buffer.name == "Skiff"
                && harness.simulator.vessels.first { $0.id == createdProfile.id }?.name == "Skiff"
                && store.saveCount > savesAfterCreate
        }
        try #require(renamed, "the name field did not autosave: field=\(nameField.stringValue) buffer=\(session.buffer.name)")
        // Grouped form fields have no placeholder. After Name, Builder, Model, Year, Sail number, and Registration, the next field is LOA.
        let lengthReady = harness.waitUntil {
            harness.revealBoatEditor()
            let fields = harness.textFields(in: boatHost)
            guard fields.count > 6 else { return false }
            let length = fields[6]
            return length.isEditable && length.stringValue.isEmpty && length.bounds.width > 20
        }
        try #require(lengthReady, "LOA field was not editable: \(harness.textFields(in: boatHost).map { $0.placeholderString ?? $0.stringValue })")
        let lengthField = try #require(harness.textFields(in: boatHost).dropFirst(6).first)
        let savesAfterName = store.saveCount
        try #require(harness.replaceText(lengthField, with: "12."))
        let held = harness.waitUntil {
            session.buffer.lengthOverall == "12."
                && session.validationMessage != nil
                && session.lastChangeSucceeded == false
                && harness.simulator.vessels.first { $0.id == createdProfile.id }?.hull.lengthOverallMeters == nil
                && store.saveCount == savesAfterName
        }
        try #require(held, "incomplete length overwrote the profile: field=\(lengthField.stringValue) status=\(session.validationMessage ?? "nil") loa=\(String(describing: harness.simulator.vessels.first { $0.id == createdProfile.id }?.hull.lengthOverallMeters))")
        try #require(harness.replaceText(lengthField, with: "12.5"))
        let measured = harness.waitUntil {
            harness.simulator.vessels.first { $0.id == createdProfile.id }?.hull.lengthOverallMeters == 12.5
                && session.validationMessage == nil
                && session.lastChangeSucceeded
        }
        try #require(measured, "the valid length did not autosave: field=\(lengthField.stringValue) status=\(session.validationMessage ?? "nil")")

        harness.select(.dashboard)
        harness.select(.boat)
        let returned = harness.waitUntil {
            boatHost.isPageActive
                && harness.sessionMarker() === sessionMarker
                && session.highlightedID == createdProfile.id
                && session.buffer.name == "Skiff"
                && nameField.stringValue == "Skiff"
                && harness.simulator.vessels.first { $0.id == createdProfile.id }?.hull.lengthOverallMeters == 12.5
                && harness.destinationHost(.manual) == nil
        }
        try #require(returned, "navigation did not keep the autosaved profile: \(harness.describe())")

        let reloadedDefaults = UserDefaults(suiteName: "BoatAutosaveReload.\(UUID().uuidString)")!
        let reloaded = NMEASimulator(userDefaults: reloadedDefaults, vesselStore: store)
        let stored = try #require(reloaded.vessels.first { $0.id == createdProfile.id })
        #expect(stored.name == "Skiff")
        #expect(stored.origin == .custom)
        #expect(stored.hull.lengthOverallMeters == 12.5)
        #expect(reloaded.vessels.first { $0.id == BuiltInVesselID.extasy }?.name == "Extasy")
        #expect(reloaded.vessels.first { $0.id == BuiltInVesselID.extasy }?.origin == .builtIn)
    }

    @Test(.timeLimit(.minutes(2)))
    func inactiveBoatDropsFocusHitTestingAndLayout() throws {
        let harness = try DestinationHarness(selection: .boat)
        defer { harness.close() }

        let warmed = harness.waitUntil {
            guard let boat = harness.destinationHost(.boat) else { return false }
            return boat.root.frame.width > 300
                && boat.root.performedLayoutCount > 0
                && boat.isPageActive
                && harness.destinationHost(.manual) == nil
        }
        try #require(warmed, "boat did not finish its first layout: \(harness.describe())")
        let boatHost = try #require(harness.destinationHost(.boat))
        let boatLayouts = boatHost.root.performedLayoutCount
        #if DEBUG
        let boatBodies = RetainedDestinationBodyProbe.boatEvaluations
        #endif

        let boatFieldReady = harness.waitUntil {
            harness.revealBoatEditor()
            return harness.editableBoatField(in: boatHost) != nil
        }
        try #require(boatFieldReady, "boat did not present an editable field: \(harness.describe())")
        let boatField = try #require(harness.editableBoatField(in: boatHost))
        let boatPolicy = FieldPolicy(boatField)
        try #require(harness.focus(boatField), "the boat field refused focus while the page was active")

        harness.select(.manual)
        let manualShown = harness.waitUntil {
            harness.manualSearchFields().isEmpty == false
                && harness.destinationHost(.manual) == nil
                && harness.isHostParked(.boat)
                && boatField.currentEditor() == nil
                && harness.responderIsInside(boatHost) == false
                && boatField.canBecomeKeyView == false
                && harness.isHiddenFromAccessibility(boatField)
                && boatHost.isAccessibilityHidden()
                && boatHost.hitTest(NSPoint(x: 8, y: 8)) == nil
                && harness.anchors(in: boatHost).allSatisfy { $0.isBoundToConsoleEdge == false }
                && boatPolicy.matches(boatField)
        }
        try #require(manualShown, "manual did not park the boat host: \(harness.describe())")
        _ = harness.window.makeFirstResponder(boatField)
        #expect(boatField.currentEditor() == nil)
        #expect(harness.hit(atCenterOf: harness.host)?.isDescendant(of: boatHost) != true)
        #expect(boatHost.root.performedLayoutCount == boatLayouts)

        harness.select(.diagnostics)
        let diagnostics = harness.waitUntil {
            harness.showsDiagnosticsPage()
                && harness.manualSearchFields().isEmpty
                && harness.destinationHost(.manual) == nil
                && harness.isHostParked(.boat)
        }
        try #require(diagnostics, "diagnostics did not release manual: \(harness.describe())")

        harness.select(.boat)
        let boatAgain = harness.waitUntil {
            boatHost.isPageActive
                && harness.showsDiagnosticsPage() == false
                && harness.destinationHost(.manual) == nil
                && boatHost.root.frame.size == boatHost.bounds.size
        }
        try #require(boatAgain, "boat did not return: \(harness.describe())")
        #expect(boatHost.root.performedLayoutCount == boatLayouts)
        #expect(boatPolicy.matches(boatField))
        #if DEBUG
        #expect(RetainedDestinationBodyProbe.boatEvaluations == boatBodies)
        #endif
    }

    @Test(.timeLimit(.minutes(2)))
    func dashboardWindReadoutUpdatesWithoutNavigation() throws {
        let harness = try DestinationHarness(selection: .dashboard, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let ready = harness.waitUntil {
            harness.textFields(in: harness.host).contains { $0.stringValue == "180" }
        }
        try #require(ready, "dashboard did not show the wind setpoint: \(harness.visibleTextSample()) fields=\(harness.textFields(in: harness.host).map(\.stringValue))")
        harness.simulator.twd.centerValue = 123
        harness.simulator.twd.value = 123
        let updated = harness.waitUntilRendered {
            harness.textFields(in: harness.host).contains { $0.stringValue == "123" }
                && (RetainedDestinationBodyProbe.readings["True Wind Direction"]?.contains("123") == true)
        }
        try #require(
            updated,
            "model=\(harness.simulator.twd.value ?? -1)/\(harness.simulator.twd.centerValue) reading=\(RetainedDestinationBodyProbe.readings["True Wind Direction"] ?? "nil") fields=\(harness.textFields(in: harness.host).map(\.stringValue))"
        )
        harness.expectStaticText("Reading True Wind Direction")
        #expect(RetainedDestinationBodyProbe.readings["True Wind Direction"]?.contains("123") == true)
        #expect(harness.textFields(in: harness.host).contains { $0.isEditable })
    }

    @Test(.timeLimit(.minutes(2)))
    func connectionEditsAppearWithoutNavigation() throws {
        let harness = try DestinationHarness(selection: .connection, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let ready = harness.waitUntil {
            harness.destinationHost(.connection)?.isPageActive == true && harness.containsVisibleText("Primary Output")
        }
        try #require(ready, "connection did not show the primary endpoint: \(harness.visibleTextSample())")
        let host = try #require(harness.destinationHost(.connection))
        let root = host.root
        harness.simulator.outputEndpoints[0].name = "Harbor Link"
        let renamed = harness.waitUntilRendered { harness.containsVisibleText("Harbor Link") }
        try #require(renamed, "name stayed stale: model=\(harness.simulator.outputEndpoints[0].name) ui=\(harness.visibleTextSample())")
        let before = harness.simulator.outputEndpoints.count
        harness.simulator.addOutputEndpoint()
        let added = harness.waitUntilRendered {
            harness.simulator.outputEndpoints.count == before + 1 && harness.containsVisibleText("Output 2")
        }
        try #require(added, "add stayed stale: count=\(harness.simulator.outputEndpoints.count) ui=\(harness.visibleTextSample())")
        let addedID = harness.simulator.outputEndpoints[1].id
        harness.simulator.removeOutputEndpoint(id: addedID)
        let removed = harness.waitUntilRendered {
            harness.simulator.outputEndpoints.count == before && harness.containsVisibleText("Output 2") == false
        }
        try #require(removed, "delete stayed visible: count=\(harness.simulator.outputEndpoints.count) ui=\(harness.visibleTextSample())")
        let toggle = try #require(harness.timerSwitch(in: host), "Enable Timer switch was missing: \(harness.switches(in: host).map { "state=\($0.state.rawValue) label=\(String(describing: $0.accessibilityLabel())) id=\($0.accessibilityIdentifier())" }) probe=\(RetainedDestinationBodyProbe.timerStatusEvaluations):\(RetainedDestinationBodyProbe.timerStatus)")
        #expect(toggle.state == .on)
        toggle.performClick(nil)
        let toggledOff = harness.waitUntilRendered {
            harness.simulator.isTimerSelected == false
                && RetainedDestinationBodyProbe.timerStatus.contains("Timer disabled")
                && harness.timerSwitch(in: host)?.state == .off
                && harness.steppers(in: host).allSatisfy { $0.isEnabled == false }
        }
        try #require(
            toggledOff,
            "timer toggle stayed stale: selected=\(harness.simulator.isTimerSelected) switch=\(String(describing: harness.timerSwitch(in: host)?.state.rawValue)) steppers=\(harness.steppers(in: host).map { "\($0.doubleValue) enabled=\($0.isEnabled)" }) probe=\(RetainedDestinationBodyProbe.timerStatusEvaluations):\(RetainedDestinationBodyProbe.timerStatus) nodes=\(harness.nodesContaining("timer", in: harness.host)) ui=\(harness.visibleTextSample())"
        )
        harness.simulator.interval = 2.5
        harness.simulator.isTimerSelected = true
        let mutated = harness.waitUntilRendered {
            RetainedDestinationBodyProbe.timerStatus.contains("Continuous timer mode")
                && RetainedDestinationBodyProbe.intervalLabel == "2.5"
                && harness.timerSwitch(in: host)?.state == .on
                && harness.steppers(in: host).contains { $0.isEnabled }
        }
        try #require(
            mutated,
            "direct timer mutation stayed stale: selected=\(harness.simulator.isTimerSelected) interval=\(harness.simulator.interval) status=\(RetainedDestinationBodyProbe.timerStatus) label=\(RetainedDestinationBodyProbe.intervalLabel) switch=\(String(describing: harness.timerSwitch(in: host)?.state.rawValue)) steppers=\(harness.steppers(in: host).map { "\($0.doubleValue) enabled=\($0.isEnabled)" })"
        )
        harness.expectStaticText("Timer Status")
        harness.expectStaticText("Send Interval")
        #expect(RetainedDestinationBodyProbe.intervalLabel == "2.5")
        #expect(harness.textFields(in: host).contains { $0.isEditable && $0.stringValue == "2.5" } == false)
        #expect(harness.destinationHost(.connection) === host)
        #expect(host.root === root)
    }

    @Test(.timeLimit(.minutes(2)))
    func dashboardLiveControlsUpdateWithoutNavigation() throws {
        let harness = try DestinationHarness(selection: .dashboard, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let windReady = harness.waitUntil {
            harness.textFields(in: harness.host).contains { $0.stringValue == "180" }
                && RetainedDestinationBodyProbe.readings["True Wind Direction"] != nil
        }
        try #require(windReady, "wind controls were missing: \(harness.visibleTextSample()) reading=\(RetainedDestinationBodyProbe.readings["True Wind Direction"] ?? "nil")")

        var windDirection = harness.simulator.twd
        windDirection.offset = 12
        windDirection.centerValue = 137
        windDirection.value = 137
        harness.simulator.twd = windDirection
        let wind = harness.waitUntilRendered {
            harness.editableField(showing: "137") != nil
                && harness.editableField(showing: "12") != nil
                && (RetainedDestinationBodyProbe.readings["True Wind Direction"]?.contains("137") == true)
        }
        try #require(wind, "wind stayed stale: fields=\(harness.textFields(in: harness.host).map(\.stringValue)) reading=\(RetainedDestinationBodyProbe.readings["True Wind Direction"] ?? "nil")")
        harness.expectStaticText("Reading True Wind Direction")
        #expect(harness.editableField(showing: "12") != nil)
        #expect(RetainedDestinationBodyProbe.readings["True Wind Direction"]?.contains("137") == true)
        try #require(harness.commitField(showing: "137", text: "141"))
        let windEdited = harness.waitUntilRendered {
            abs(harness.simulator.twd.centerValue - 141) < 0.01 && harness.containsVisibleText("141")
        }
        try #require(windEdited, "wind edit stayed stale: center=\(harness.simulator.twd.centerValue) ui=\(harness.visibleTextSample())")

        try #require(harness.selectSegment(labeled: "Environment"), "environment segment did not respond")
        let environmentReady = harness.waitUntilRendered { RetainedDestinationBodyProbe.readings["Relative Humidity"] != nil }
        try #require(environmentReady, "environment controls were missing: \(RetainedDestinationBodyProbe.readings)")
        harness.simulator.humidity.centerValue = 77
        harness.simulator.humidity.value = 77
        let environment = harness.waitUntilRendered {
            harness.editableField(showing: "77") != nil
                && (RetainedDestinationBodyProbe.readings["Relative Humidity"]?.contains("77") == true)
        }
        try #require(environment, "humidity stayed stale: fields=\(harness.textFields(in: harness.host).map(\.stringValue)) reading=\(RetainedDestinationBodyProbe.readings["Relative Humidity"] ?? "nil")")
        harness.expectStaticText("Reading Relative Humidity")
        #expect(RetainedDestinationBodyProbe.readings["Relative Humidity"]?.contains("77") == true)
        var sensors = harness.simulator.sensorToggles
        sensors.hasHumidtySensor = true
        harness.simulator.sensorToggles = sensors
        let humidityEditable = harness.waitUntilRendered { harness.editableField(showing: "77")?.isEnabled == true }
        try #require(humidityEditable, "humidity field stayed disabled")
        try #require(harness.commitField(showing: "77", text: "66"))
        let environmentEdited = harness.waitUntilRendered { abs(harness.simulator.humidity.centerValue - 66) < 0.01 }
        try #require(environmentEdited, "humidity edit stayed stale: center=\(harness.simulator.humidity.centerValue)")

        try #require(harness.selectSegment(labeled: "Hydro"))
        let hydroReady = harness.waitUntilRendered { RetainedDestinationBodyProbe.readings["Speed Through Water"] != nil }
        try #require(hydroReady, "hydro controls were missing: \(RetainedDestinationBodyProbe.readings)")
        harness.simulator.speed.centerValue = 8.5
        harness.simulator.speed.value = 8.5
        let speedText = harness.formattedNumber(8.5, fractionDigits: 1)
        let hydro = harness.waitUntilRendered {
            harness.editableField(showing: speedText) != nil
                && (RetainedDestinationBodyProbe.readings["Speed Through Water"]?.contains(speedText) == true)
        }
        try #require(hydro, "speed stayed stale: expected \(speedText) fields=\(harness.textFields(in: harness.host).map(\.stringValue)) reading=\(RetainedDestinationBodyProbe.readings["Speed Through Water"] ?? "nil")")
        harness.expectStaticText("Reading Speed Through Water")
        #expect(RetainedDestinationBodyProbe.readings["Speed Through Water"]?.contains(speedText) == true)
        let editedSpeed = harness.formattedNumber(9.5, fractionDigits: 1)
        try #require(harness.commitField(showing: speedText, text: editedSpeed))
        let hydroEdited = harness.waitUntilRendered { abs(harness.simulator.speed.centerValue - 9.5) < 0.01 }
        try #require(hydroEdited, "speed edit stayed stale: center=\(harness.simulator.speed.centerValue)")

        try #require(harness.selectSegment(labeled: "Heading"))
        let headingReady = harness.waitUntilRendered {
            RetainedDestinationBodyProbe.readings["Heading Status"] != nil
                && RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] != nil
        }
        try #require(headingReady, "heading controls were missing: \(RetainedDestinationBodyProbe.readings)")
        harness.simulator.gyroHeading.centerValue = 244
        harness.simulator.gyroHeading.value = 244
        let heading = harness.waitUntilRendered {
            harness.editableField(showing: "244") != nil
                && (RetainedDestinationBodyProbe.readings["Heading Status"]?.contains("244") == true)
                && (RetainedDestinationBodyProbe.readings["Gyro Compass (True)"]?.contains("244") == true)
        }
        try #require(heading, "heading controls stayed stale: fields=\(harness.textFields(in: harness.host).map(\.stringValue)) readings=\(RetainedDestinationBodyProbe.readings)")
        harness.expectStaticText("Heading Status")
        harness.expectStaticText("Reading Gyro Compass (True)")
        try #require(harness.commitField(showing: "244", text: "250"))
        let headingEdited = harness.waitUntilRendered {
            abs(harness.simulator.gyroHeading.centerValue - 250) < 0.01 && harness.containsVisibleText("250")
        }
        try #require(headingEdited, "heading edit stayed stale: center=\(harness.simulator.gyroHeading.centerValue) ui=\(harness.visibleTextSample())")

        try #require(harness.selectSegment(labeled: "Boat"), "boat tab did not respond")
        let boatReady = harness.waitUntilRendered {
            harness.containsVisibleText("Manual") && harness.containsVisibleText("From Wind")
        }
        try #require(boatReady, "boat controls were missing: \(harness.visibleTextSample())")
    }

    @Test(.timeLimit(.minutes(2)))
    func dashboardHeadingLiveGyroFollowsSetpointAfterSimulationUpdate() throws {
        let harness = try DestinationHarness(selection: .dashboard, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let ready = harness.waitUntil {
            harness.textFields(in: harness.host).contains { $0.stringValue == "180" }
        }
        try #require(ready, "dashboard did not appear: \(harness.visibleTextSample())")

        var gyro = harness.simulator.gyroHeading
        gyro.centerValue = 6
        gyro.offset = 0
        gyro.value = 6
        harness.simulator.setSimulatedValue(\.gyroHeading, to: gyro)

        try #require(harness.selectSegment(labeled: "Heading"), "heading tab did not respond")
        let shown = harness.waitUntilRendered {
            harness.editableField(showing: "6") != nil
                && RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] == "6 °"
        }
        try #require(
            shown,
            "heading card did not show the live gyro: fields=\(harness.textFields(in: harness.host).map(\.stringValue)) reading=\(RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] ?? "nil")"
        )

        try #require(harness.commitField(showing: "6", text: "39"))
        let commanded = harness.waitUntilRendered {
            harness.editableField(showing: "39") != nil
                && RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] == "6 °"
                && abs((harness.simulator.gyroHeading.value ?? -1) - 6) < 0.001
        }
        try #require(
            commanded,
            "live gyro changed before the simulation update: value=\(harness.simulator.gyroHeading.value ?? -1) center=\(harness.simulator.gyroHeading.centerValue) reading=\(RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] ?? "nil") fields=\(harness.textFields(in: harness.host).map(\.stringValue))"
        )

        harness.simulator.outputEndpoints[0].isEnabled = false
        harness.simulator.runSimulationCycle(at: Date())
        let updated = harness.waitUntilRendered {
            RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] == "39 °"
        }
        let live = harness.simulator.gyroHeading.value ?? -1
        try #require(
            updated,
            "live gyro stayed stale after the heading update: value=\(live) reading=\(RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] ?? "nil") fields=\(harness.textFields(in: harness.host).map(\.stringValue))"
        )
        harness.expectStaticText("Reading Gyro Compass (True)")
        #expect(abs(live - 39) < 0.05)
        #expect(RetainedDestinationBodyProbe.readings["Gyro Compass (True)"] == "39 °")
        if let readout = harness.staticReadout("Reading Gyro Compass (True)", in: harness.host), readout.text.isEmpty == false {
            #expect(readout.text.contains("39"))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func focusedSetpointKeepsIntermediateText() throws {
        let harness = try DestinationHarness(selection: .dashboard, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let ready = harness.waitUntil { harness.editableField(showing: "180") != nil }
        let field = try #require(ready ? harness.editableField(showing: "180") : nil, "setpoint field was missing: \(harness.textFields(in: harness.host).map(\.stringValue))")
        try #require(harness.replaceText(field, with: "12x"))
        harness.simulator.twd.centerValue = 150
        harness.simulator.twd.value = 150
        let preserved = harness.waitUntilRendered { field.stringValue == "12x" }
        try #require(preserved, "focused draft was replaced: field=\(field.stringValue) model=\(harness.simulator.twd.centerValue)")
        harness.window.makeFirstResponder(nil)
        let accepted = harness.waitUntilRendered {
            field.stringValue == "150" && abs(harness.simulator.twd.centerValue - 150) < 0.01
        }
        try #require(accepted, "unfocused field did not accept the model: field=\(field.stringValue) model=\(harness.simulator.twd.centerValue)")
    }

    @Test(.timeLimit(.minutes(2)))
    func toolbarStatusUpdatesWhileDashboardIsMounted() throws {
        let harness = try DestinationHarness(selection: .dashboard, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let ready = harness.waitUntil {
            harness.toolbarSample().localizedCaseInsensitiveContains("Start")
        }
        try #require(ready, "toolbar was missing: \(harness.toolbarSample())")
        harness.simulator.outputEndpoints[0].name = "Harbor Link"
        harness.simulator.latestTransportStatus = OutputEndpointStatus(
            endpointID: harness.simulator.outputEndpoints[0].id,
            level: .connected,
            message: "Relay check"
        )
        harness.simulator.isTransmitting = true
        let updated = harness.waitUntilRendered {
            harness.toolbarSample().localizedCaseInsensitiveContains("Stop")
        }
        try #require(updated, "toolbar stayed stale: \(harness.toolbarSample())")
    }

    @Test(.timeLimit(.minutes(2)))
    func simulationSensorsAreReachableOnAFreshCompactMount() throws {
        let harness = try DestinationHarness(
            selection: .simulation,
            windowWidth: 960,
            windowHeight: 700,
            initialSidebar: 300
        )
        defer { harness.close() }
        let ready = harness.waitUntil {
            guard let width = harness.setupContentWidth() else { return false }
            return width < ResponsiveLayout.targetMinimumContentWidth
                && harness.revealSensors() != nil
                && harness.sensorsAreReachable()
        }
        try #require(ready, "Onboard Sensors was missing on a fresh compact mount: \(harness.sensorReport())")
    }

    @Test(.timeLimit(.minutes(2)))
    func simulationSensorsAreReachableOnAFreshWideMount() throws {
        let harness = try DestinationHarness(
            selection: .simulation,
            windowWidth: 1680,
            windowHeight: 900,
            initialSidebar: 220
        )
        defer { harness.close() }
        let ready = harness.waitUntil {
            guard let width = harness.setupContentWidth() else { return false }
            return width >= DesignToken.Breakpoint.wide
                && harness.revealSensors() != nil
                && harness.sensorsAreReachable()
        }
        try #require(ready, "Onboard Sensors was missing on a fresh wide mount: \(harness.sensorReport())")
    }

    @Test(.timeLimit(.minutes(2)))
    func simulationSensorsStayReachableAfterNavigationAndWidthChange() throws {
        let harness = try DestinationHarness(selection: .simulation, windowWidth: 1180, windowHeight: 760)
        defer { harness.close() }

        let firstVisit = harness.waitUntil {
            harness.revealSensors() != nil && harness.sensorsAreReachable()
        }
        try #require(firstVisit, "Onboard Sensors was missing on the first visit: \(harness.sensorReport())")
        let simulationHost = try #require(harness.destinationHost(.simulation))
        let simulationRoot = simulationHost.root
        let card = try #require(harness.revealSensors())
        #expect(card.bounds.width > 12)
        #expect(card.bounds.height > 12)

        harness.select(.dashboard)
        let parked = harness.waitUntil { harness.isHostParked(.simulation) }
        try #require(parked, "simulation did not park: \(harness.describe())")
        harness.select(.simulation)
        let returned = harness.waitUntil {
            simulationHost.isPageActive
                && harness.destinationHost(.simulation) === simulationHost
                && simulationHost.root === simulationRoot
                && harness.sensorsAreReachable()
        }
        try #require(returned, "Onboard Sensors did not survive navigation: \(harness.sensorReport())")

        harness.layoutPage(windowSize: NSSize(width: 960, height: 700), sidebar: 300)
        let compact = harness.waitUntil {
            guard let width = harness.setupContentWidth() else { return false }
            return width < ResponsiveLayout.targetMinimumContentWidth && harness.sensorsAreReachable()
        }
        try #require(compact, "sensors were not reachable at compact width: \(harness.sensorReport())")

        harness.layoutPage(windowSize: NSSize(width: 1680, height: 900), sidebar: 220)
        let wide = harness.waitUntil {
            guard let width = harness.setupContentWidth() else { return false }
            return width >= DesignToken.Breakpoint.wide && harness.sensorsAreReachable()
        }
        try #require(wide, "sensors were not reachable at wide width: \(harness.sensorReport())")
        #expect(harness.destinationHost(.simulation) === simulationHost)
        #expect(simulationHost.root === simulationRoot)
    }

    @Test(.timeLimit(.minutes(2)))
    func boatSelectionRefreshesDetailBeforeAnyDeletion() throws {
        let harness = try DestinationHarness(selection: .boat, windowWidth: 1280, windowHeight: 860)
        defer { harness.close() }
        let deleteRequests = VesselDeletePrompt.requestCount

        let ready = harness.waitUntil {
            guard let boatHost = harness.destinationHost(.boat), boatHost.isPageActive, boatHost.root.frame.width > 300 else {
                return false
            }
            return harness.sessionMarker()?.session?.highlightedID == BuiltInVesselID.extasy
                && harness.detailShows(extasyDetailMarkers, in: boatHost)
        }
        try #require(ready, "the first visit did not show Extasy: \(harness.detailReport())")
        let boatHost = try #require(harness.destinationHost(.boat))
        let boatRoot = boatHost.root
        let sessionMarker = try #require(harness.sessionMarker())
        let session = try #require(sessionMarker.session)
        let vesselIDs = Set(harness.simulator.vessels.map(\.id))

        try #require(harness.selectLibraryRow(named: "Nimana", in: boatHost))
        let nimana = harness.waitUntil {
            session.highlightedID == BuiltInVesselID.nimana
                && harness.sessionMarker() === sessionMarker
                && harness.sessionMarker()?.session === session
                && harness.detailShows(nimanaDetailMarkers, in: boatHost)
                && harness.detailLacks(extasyOnlyMarkers, in: boatHost)
        }
        try #require(nimana, "selecting Nimana did not refresh the detail: \(harness.detailReport())")

        try #require(harness.selectLibraryRow(named: "Extasy", in: boatHost))
        let extasyAgain = harness.waitUntil {
            session.highlightedID == BuiltInVesselID.extasy
                && harness.detailShows(extasyDetailMarkers, in: boatHost)
                && harness.detailLacks(nimanaOnlyMarkers, in: boatHost)
        }
        try #require(extasyAgain, "selecting Extasy again left Nimana values on screen: \(harness.detailReport())")

        let pressed = harness.pressNewVessel(in: boatHost)
        let created = harness.waitUntil {
            let profile = harness.simulator.vessels.first { $0.name == "Custom Vessel" }
            return pressed
                && profile?.origin == .custom
                && session.highlightedID == profile?.id
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Custom Vessel" && $0.isEditable && $0.bounds.width > 20 }
        }
        try #require(created, "New did not show an editable custom vessel before any deletion: \(harness.detailReport())")
        let customID = try #require(harness.simulator.vessels.first { $0.name == "Custom Vessel" }?.id)

        try #require(harness.selectLibraryRow(named: "Nimana", in: boatHost))
        let nimanaAfterCustom = harness.waitUntil {
            session.highlightedID == BuiltInVesselID.nimana
                && harness.detailShows(nimanaDetailMarkers, in: boatHost)
                && harness.detailLacks(["Custom Vessel"], in: boatHost)
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Custom Vessel" && $0.isEditable } == false
        }
        try #require(nimanaAfterCustom, "Nimana did not replace the custom vessel detail: \(harness.detailReport())")

        try #require(harness.selectLibraryRow(named: "Custom Vessel", in: boatHost))
        let customAgain = harness.waitUntil {
            session.highlightedID == customID
                && harness.textFields(in: boatHost).contains { $0.stringValue == "Custom Vessel" && $0.isEditable && $0.bounds.width > 20 }
                && harness.detailLacks(extasyOnlyMarkers, in: boatHost)
        }
        try #require(customAgain, "returning to the custom vessel did not restore its detail: \(harness.detailReport())")

        #expect(harness.destinationHost(.boat) === boatHost)
        #expect(boatHost.root === boatRoot)
        #expect(harness.sessionMarker() === sessionMarker)
        #expect(harness.sessionMarker()?.session === session)
        #expect(vesselIDs.isSubset(of: Set(harness.simulator.vessels.map(\.id))))
        #expect(harness.simulator.vessels.contains { $0.id == BuiltInVesselID.extasy })
        #expect(harness.simulator.vessels.contains { $0.id == BuiltInVesselID.nimana })
        #expect(VesselDeletePrompt.requestCount == deleteRequests)
        #expect(VesselDeletePrompt.presentedVesselID == nil)
    }
}

private let extasyDetailMarkers = ["Beneteau First 40.7", "11.924 m", "14.710 m", "7272 kg", "Mainsail 1"]
private let nimanaDetailMarkers = ["Bavaria Cruiser 46", "13.600 m", "16.550 m", "12888 kg", "Mainsail 0"]
private let extasyOnlyMarkers = extasyDetailMarkers
private let nimanaOnlyMarkers = nimanaDetailMarkers

private struct FieldPolicy: Equatable {
    var refusesFirstResponder: Bool
    var isEnabled: Bool
    var isEditable: Bool
    var isSelectable: Bool

    init(_ field: NSTextField) {
        refusesFirstResponder = field.refusesFirstResponder
        isEnabled = field.isEnabled
        isEditable = field.isEditable
        isSelectable = field.isSelectable
    }

    func matches(_ field: NSTextField) -> Bool {
        self == FieldPolicy(field)
    }
}

@MainActor
private final class DestinationHarness {
    let simulator: NMEASimulator
    let host: NSView
    let window: NSWindow
    private let defaults: UserDefaults
    private let suite: String
    private let standardSnapshot: [(String, Any?)]

    init(
        selection: SidebarItem,
        consoleHeight: Double = 200,
        windowWidth: CGFloat = 1180,
        windowHeight: CGFloat = 760,
        initialSidebar: CGFloat? = nil,
        vesselStore: (any VesselProfileStoring)? = nil
    ) throws {
        suite = "RetainedDestinationLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(selection.rawValue, forKey: "main_view.selection")
        defaults.set(consoleHeight, forKey: ConsoleHeightStorage.key)
        self.defaults = defaults
        standardSnapshot = [
            ConsoleHeightStorage.key,
            "main_view.selection",
        ].map { ($0, UserDefaults.standard.object(forKey: $0)) }

        let simulator = NMEASimulator(userDefaults: defaults, vesselStore: vesselStore)
        self.simulator = simulator
        let root = NSHostingView(rootView: MainView(nmeaManager: simulator).defaultAppStorage(defaults))
        host = root
        window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.contentView = root
        root.autoresizingMask = [.width, .height]
        if let initialSidebar {
            root.layoutSubtreeIfNeeded()
            let splits = views(in: root).compactMap { $0 as? NSSplitView }.filter { $0.bounds.width > 400 }
            splits.max(by: { $0.bounds.width < $1.bounds.width })?.setPosition(initialSidebar, ofDividerAt: 0)
            root.layoutSubtreeIfNeeded()
        }
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.close()
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in standardSnapshot {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #if DEBUG
        ScrollRuntimeTrace.shared.resetForTest()
        #endif
    }

    func select(_ item: SidebarItem) {
        defaults.set(item.rawValue, forKey: "main_view.selection")
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
    }

    func scroll(_ scroll: NSScrollView, to y: CGFloat) {
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
        boundAnchors(in: scroll).forEach { $0.followViewport() }
    }

    @discardableResult
    func waitUntil(timeout: TimeInterval = 5, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            CATransaction.flush()
            host.layoutSubtreeIfNeeded()
            if predicate() { return true }
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Pumps the run loop without forcing a layout pass. A view that only changes after `layoutSubtreeIfNeeded` is not invalidating itself.
    @discardableResult
    func waitUntilRendered(timeout: TimeInterval = 2, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            CATransaction.flush()
            if predicate() { return true }
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func containsVisibleText(_ needle: String) -> Bool {
        strings(in: host).contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    func visibleTextSample() -> String {
        strings(in: host).filter { $0.count > 2 && $0.count < 48 }.prefix(30).joined(separator: "|")
    }

    func isHostParked(_ page: SidebarItem) -> Bool {
        guard let pageHost = destinationHost(page) else { return false }
        return pageHost.isPageActive == false
            && pageHost.isHidden
            && pageHost.alphaValue == 0
            && pageHost.bounds.width <= 1
            && pageHost.bounds.height <= 1
    }

    /// The stable host leaves the column. The hosted form keeps its last size and is not laid out again.
    func isParked(_ scroll: NSScrollView) -> Bool {
        guard let pageHost = destinationHost(containing: scroll) else { return false }
        return pageHost.isPageActive == false
            && pageHost.bounds.width <= 1
            && pageHost.bounds.height <= 1
    }

    func destinationHost(_ page: SidebarItem) -> (any RetainedDestinationHosting)? {
        views(in: host).compactMap { $0 as? any RetainedDestinationHosting }.first { $0.page == page }
    }

    func destinationHost(containing view: NSView) -> (any RetainedDestinationHosting)? {
        var current: NSView? = view
        while let node = current {
            if let pageHost = node as? any RetainedDestinationHosting { return pageHost }
            current = node.superview
        }
        return nil
    }

    func marker(_ page: SidebarItem) -> RetainedDestinationMarkerView? {
        markers().first { $0.page == page }
    }

    func markers() -> [RetainedDestinationMarkerView] {
        views(in: host).compactMap { $0 as? RetainedDestinationMarkerView }
    }

    func boundAnchors(in scroll: NSView) -> [ConsoleEdgeAnchorView] {
        views(in: scroll).compactMap { $0 as? ConsoleEdgeAnchorView }.filter(\.isBoundToConsoleEdge)
    }

    func consoleHosts() -> [NSView] {
        views(in: host).filter { String(describing: type(of: $0)).contains("ConsoleLogHost") }
    }

    func mapHosts() -> [BoatMapContainerView] {
        views(in: host).compactMap { $0 as? BoatMapContainerView }
    }

    func largeMapViews() -> [MKMapView] {
        views(in: host).compactMap { view in
            guard let map = view as? MKMapView,
                  !map.isHiddenOrHasHiddenAncestor,
                  map.bounds.width > 2,
                  map.bounds.height > 2 else { return nil }
            return map
        }
    }

    func manualSearchFields() -> [NSView] {
        views(in: host).filter { view in
            guard let field = view as? NSTextField else { return false }
            let placeholder = field.placeholderString ?? field.placeholderAttributedString?.string ?? ""
            return placeholder.localizedCaseInsensitiveContains("search manual")
        }
    }

    func switchControl(labeled title: String, in root: NSView) -> NSSwitch? {
        views(in: root).compactMap { $0 as? NSSwitch }.first { control in
            var view: NSView? = control
            while let node = view {
                if accessibilityText(of: node).contains(where: { $0.localizedCaseInsensitiveContains(title) || $0 == title }) {
                    return true
                }
                view = node.superview
            }
            var element: NSObject? = control
            var hops = 0
            while let node = element, hops < 8 {
                if accessibilityText(of: node).contains(where: { $0.localizedCaseInsensitiveContains(title) || $0 == title }) {
                    return true
                }
                element = accessibilityParent(of: node)
                hops += 1
            }
            return false
        }
    }

    func textFields(in root: NSView) -> [NSTextField] {
        views(in: root).compactMap { $0 as? NSTextField }
    }

    func steppers(in root: NSView) -> [NSStepper] {
        views(in: root).compactMap { $0 as? NSStepper }
    }

    func switches(in root: NSView) -> [NSSwitch] {
        views(in: root).compactMap { $0 as? NSSwitch }
    }

    func timerSwitch(in root: NSView) -> NSSwitch? {
        if let labeled = switchControl(labeled: "Enable Timer", in: root) { return labeled }
        let candidates = switches(in: root)
        guard let stepper = steppers(in: root).first else { return nil }
        return candidates.min { lhs, rhs in
            distance(lhs, stepper, in: root) < distance(rhs, stepper, in: root)
        }
    }

    private func distance(_ lhs: NSView, _ rhs: NSView, in root: NSView) -> CGFloat {
        let left = lhs.convert(lhs.bounds, to: root)
        let right = rhs.convert(rhs.bounds, to: root)
        return hypot(left.midX - right.midX, left.midY - right.midY)
    }

    func nodesContaining(_ needle: String, in root: NSView) -> String {
        var lines: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            let texts = controlText(of: node)
            if texts.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) {
                let view = node as? NSView
                let field = node as? NSTextField
                let textView = node as? NSTextView
                lines.append(
                    "\(type(of: node)) id=\(accessibilityIdentifier(of: node) ?? "-") role=\(accessibilityRole(of: node) ?? "-") editable=\(field?.isEditable ?? textView?.isEditable ?? false) selectable=\(field?.isSelectable ?? textView?.isSelectable ?? false) key=\(view?.canBecomeKeyView ?? false) text=\(texts.joined(separator: "/"))"
                )
            }
            for child in controlChildren(of: node) {
                visit(child)
            }
        }
        visit(root)
        return lines.joined(separator: " || ")
    }

    struct StaticReadout {
        var identifier: String
        var role: String?
        var text: String
        var isEditor: Bool
        var frame: CGRect
    }

    func expectStaticText(_ identifier: String) {
        guard let readout = staticReadout(identifier, in: host) else { return }
        #expect(readout.isEditor == false)
        #expect(readout.role != NSAccessibility.Role.textField.rawValue)
    }

    func staticReadout(_ identifier: String, in root: NSView) -> StaticReadout? {
        var match: StaticReadout?
        func visit(_ node: NSObject) {
            guard match == nil else { return }
            let nodeIdentifier = accessibilityIdentifier(of: node)
            if nodeIdentifier == identifier {
                let field = node as? NSTextField
                let role = accessibilityRole(of: node)
                let editable = field?.isEditable == true || field?.isSelectable == true
                let textFieldRole = role == NSAccessibility.Role.textField.rawValue
                match = StaticReadout(
                    identifier: identifier,
                    role: role,
                    text: controlText(of: node).joined(separator: " "),
                    isEditor: editable || textFieldRole || field?.canBecomeKeyView == true,
                    frame: (node as? NSView)?.convert((node as? NSView)?.bounds ?? .zero, to: root) ?? .zero
                )
                return
            }
            for child in controlChildren(of: node) {
                visit(child)
            }
        }
        visit(root)
        guard let readout = match else { return nil }
        return readout
    }

    func textControlSample(in root: NSView) -> String {
        views(in: root).compactMap { view -> String? in
            let text: String
            let editable: Bool
            let selectable: Bool
            if let field = view as? NSTextField {
                text = field.stringValue
                editable = field.isEditable
                selectable = field.isSelectable
            } else if let textView = view as? NSTextView {
                text = textView.string
                editable = textView.isEditable
                selectable = textView.isSelectable
            } else {
                return nil
            }
            guard text.isEmpty == false else { return nil }
            let role = view.accessibilityRole()?.rawValue ?? "-"
            let identifier = view.accessibilityIdentifier()
            return "\(type(of: view)) id=\(identifier) role=\(role) editable=\(editable) selectable=\(selectable) key=\(view.canBecomeKeyView) text=\(text)"
        }.joined(separator: " || ")
    }

    func readoutSample(in root: NSView) -> String {
        ["Timer Status", "Send Interval", "Reading True Wind Direction", "Variation True Wind Direction", "Heading Status"]
            .map { identifier in
                guard let readout = staticReadout(identifier, in: root) else { return "\(identifier)=missing" }
                return "\(identifier) role=\(readout.role ?? "-") editor=\(readout.isEditor) text=\(readout.text)"
            }
            .joined(separator: " | ")
    }

    private func accessibilityText(of node: NSObject) -> [String] {
        controlText(of: node)
    }

    private func accessibilityParent(of node: NSObject) -> NSObject? {
        let selector = NSSelectorFromString("accessibilityParent")
        guard node.responds(to: selector) else { return nil }
        return node.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    private func accessibilityIdentifier(of node: NSObject) -> String? {
        if let view = node as? NSView { return view.accessibilityIdentifier() }
        if let element = node as? NSAccessibilityElement { return element.accessibilityIdentifier() }
        if let value = axAttribute(NSAccessibility.Attribute.identifier.rawValue, on: node) { return value }
        return axString("accessibilityIdentifier", on: node)
    }

    private func accessibilityRole(of node: NSObject) -> String? {
        if let view = node as? NSView { return view.accessibilityRole()?.rawValue }
        if let element = node as? NSAccessibilityElement { return element.accessibilityRole()?.rawValue }
        return nil
    }

    func formattedNumber(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.never))
    }

    func editableField(showing text: String) -> NSTextField? {
        textFields(in: host).first { $0.isEditable && $0.stringValue == text }
    }

    @discardableResult
    func commitField(showing current: String, text: String) -> Bool {
        guard let field = editableField(showing: current) else { return false }
        guard replaceText(field, with: text) else { return false }
        window.makeFirstResponder(nil)
        return true
    }

    func toolbarSample() -> String {
        guard let toolbar = window.toolbar else { return "no-toolbar" }
        return toolbar.items.map { item in
            let inside = item.view.map { view in
                visibleNodes(in: view).flatMap { controlText(of: $0) }.joined(separator: " ")
            } ?? ""
            return [item.label, item.paletteLabel, item.toolTip ?? "", inside].filter { $0.isEmpty == false }.joined(separator: " ")
        }.joined(separator: " | ")
    }

    @discardableResult
    func selectSegment(labeled label: String) -> Bool {
        if let tabMatch = visibleNodes(in: host).first(where: { node in
            controlText(of: node).contains("ControlTab \(label)")
        }), invokePress(on: tabMatch) {
            return true
        }
        for control in views(in: host).compactMap({ $0 as? NSSegmentedControl }) {
            for index in 0..<control.segmentCount {
                if control.label(forSegment: index) == label {
                    control.selectedSegment = index
                    control.sendAction(control.action, to: control.target)
                    return true
                }
            }
        }
        if let category = ControlCategory.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(label) == .orderedSame
                || $0.segmentTitle.caseInsensitiveCompare(label) == .orderedSame
        }), let button = views(in: host).compactMap({ $0 as? NSButton }).first(where: {
            $0.accessibilityIdentifier() == "ControlTab \(category.rawValue)"
                || $0.accessibilityLabel() == category.rawValue
                || $0.toolTip == category.rawValue
        }) {
            button.performClick(nil)
            return true
        }
        if pressControl(containing: label, in: host) {
            return true
        }
        if let category = ControlCategory.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(label) == .orderedSame
                || $0.segmentTitle.caseInsensitiveCompare(label) == .orderedSame
        }) {
            defaults.set(category.rawValue, forKey: "dashboard.live_control_category")
            return true
        }
        return false
    }

    func editableField(in root: NSView) -> NSTextField? {
        textFields(in: root).first { field in
            let placeholder = field.placeholderString ?? field.placeholderAttributedString?.string ?? ""
            return field.isEditable && field.isEnabled && placeholder == "Host"
        }
    }

    @discardableResult
    func keyViewLoop(limit: Int = 80) -> [NSView] {
        window.recalculateKeyViewLoop()
        guard var current = window.contentView?.nextValidKeyView else { return [] }
        var loop: [NSView] = []
        var seen = Set<ObjectIdentifier>()
        while seen.insert(ObjectIdentifier(current)).inserted, loop.count < limit {
            loop.append(current)
            guard let next = current.nextValidKeyView else { break }
            current = next
        }
        return loop
    }

    func focus(_ field: NSTextField) -> Bool {
        window.makeFirstResponder(nil)
        guard window.makeFirstResponder(field) else { return false }
        return field.currentEditor() != nil || window.firstResponder === field
    }

    func responderIsInside(_ root: NSView) -> Bool {
        guard let responder = window.firstResponder as? NSView else { return false }
        return responder === root || responder.isDescendant(of: root)
    }

    func isHiddenFromAccessibility(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let node = current {
            if node.isAccessibilityHidden() { return true }
            current = node.superview
        }
        return false
    }

    func hit(atCenterOf view: NSView) -> NSView? {
        view.hitTest(NSPoint(x: view.bounds.midX, y: view.bounds.midY))
    }

    func anchors(in root: NSView) -> [ConsoleEdgeAnchorView] {
        views(in: root).compactMap { $0 as? ConsoleEdgeAnchorView }
    }

    func scrollViews(in root: NSView) -> [NSScrollView] {
        views(in: root).compactMap { $0 as? NSScrollView }
    }

    func tables(in root: NSView) -> [NSTableView] {
        views(in: root).compactMap { $0 as? NSTableView }
    }

    func libraryPaneDump(in root: NSView) -> String {
        guard let split = splitViews(in: root).first, let left = split.subviews.first else { return "no-split" }
        var lines: [String] = []
        func walk(_ view: NSView, depth: Int) {
            guard lines.count < 45, depth < 8 else { return }
            let title = (view as? NSButton)?.title ?? (view as? NSTextField)?.stringValue ?? ""
            let label = view.accessibilityLabel() ?? ""
            let interesting = title.isEmpty == false || label.isEmpty == false || depth < 3
            if interesting || view.subviews.isEmpty {
                lines.append("\(depth):\(type(of: view)) \(Int(view.frame.width))x\(Int(view.frame.height)) \(title.prefix(24)) \(label.prefix(24))")
            }
            for subview in view.subviews {
                walk(subview, depth: depth + 1)
            }
        }
        walk(left, depth: 0)
        return lines.joined(separator: " || ")
    }

    func splitSummary(in root: NSView) -> String {
        splitViews(in: root).map { split in
            let children = split.subviews.map { "\(Int($0.bounds.width))x\(Int($0.bounds.height))" }.joined(separator: ",")
            return "\(Int(split.bounds.width))x\(Int(split.bounds.height)) [\(children)]"
        }.joined(separator: " | ")
    }

    func nodes(containing needle: String, in root: NSView) -> String {
        let matches = visibleNodes(in: root).filter { node in
            controlText(of: node).joined(separator: " ").localizedCaseInsensitiveContains(needle)
        }
        return matches.prefix(6).map { node in
            let text = controlText(of: node).joined(separator: "/").prefix(40)
            let press = node.responds(to: NSSelectorFromString("accessibilityPerformPress"))
            if let view = node as? NSView {
                return "\(type(of: view)) \(Int(view.bounds.width))x\(Int(view.bounds.height)) press=\(press) \(text)"
            }
            return "\(type(of: node)) press=\(press) \(text)"
        }.joined(separator: " || ")
    }

    func splitViews(in root: NSView) -> [NSSplitView] {
        views(in: root).compactMap { $0 as? NSSplitView }
    }

    func sessionMarker() -> VesselLibrarySessionMarkerView? {
        views(in: host).compactMap { $0 as? VesselLibrarySessionMarkerView }.first
    }

    func showsDiagnosticsPage() -> Bool {
        laidOutText(containing: "1800")
    }

    func showsWindPage() -> Bool {
        let segments = views(in: host).compactMap { $0 as? NSSegmentedControl }.filter {
            $0.bounds.width > 20 && $0.isHiddenOrHasHiddenAncestor == false
        }
        let labels = segments.flatMap { control in
            (0..<control.segmentCount).compactMap { control.label(forSegment: $0) }
        }
        return labels.contains("Relative") && labels.contains("True")
    }

    func looseMapViews() -> [MKMapView] {
        views(in: host).compactMap { $0 as? MKMapView }.filter { map in
            guard map.bounds.width > 2, map.bounds.height > 2 else { return false }
            var current: NSView? = map
            while let node = current {
                if node is BoatMapContainerView { return false }
                current = node.superview
            }
            return true
        }
    }

    func laidOutText(containing needle: String, in root: NSView? = nil) -> Bool {
        visibleNodes(in: root ?? host).contains { node in
            controlText(of: node).joined(separator: " ").localizedCaseInsensitiveContains(needle)
        }
    }

    @discardableResult
    func replaceText(_ field: NSTextField, with text: String) -> Bool {
        guard focus(field), let editor = field.currentEditor() as? NSTextView else { return false }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        return editor.string == text || field.stringValue == text
    }

    @discardableResult
    func buttonSummary(in root: NSView) -> String {
        views(in: root).compactMap { $0 as? NSButton }.map { button in
            "\(button.title) \(Int(button.bounds.width))x\(Int(button.bounds.height)) enabled=\(button.isEnabled) hidden=\(button.isHiddenOrHasHiddenAncestor)"
        }.joined(separator: " | ")
    }

    func requireLibraryCommands(in root: NSView, deleteEnabled: Bool) throws {
        for title in ["New", "Duplicate", "Delete"] {
            let button = try #require(libraryCommand(title, in: root), "missing \(title)")
            let action = try #require(button.action)
            #expect(button.target != nil)
            #expect(button.target?.responds(to: action) == true)
            #expect(button.accessibilityLabel() == title)
            #expect(button.accessibilityIdentifier() == title)
        }
        #expect(libraryCommand("New", in: root)?.isEnabled == true)
        #expect(libraryCommand("Duplicate", in: root)?.isEnabled == true)
        #expect(libraryCommand("Delete", in: root)?.isEnabled == deleteEnabled)
    }

    func libraryCommand(_ title: String, in root: NSView) -> NSButton? {
        views(in: root).compactMap { $0 as? NSButton }.first { button in
            button.title == title && button.bounds.width > 2 && button.bounds.height > 2
        }
    }

    func pressNewVessel(in root: NSView) -> Bool {
        root.layoutSubtreeIfNeeded()
        let button = views(in: root).compactMap { $0 as? NSButton }.first { candidate in
            candidate.title == "New" && candidate.isEnabled && candidate.isHiddenOrHasHiddenAncestor == false
        }
        if let button {
            button.performClick(nil)
            return true
        }
        if pressControl(containing: "New Vessel", in: root) || pressControl(containing: "New", in: root) {
            return true
        }
        return clickFocusRing(at: 0, in: root)
    }

    @discardableResult
    func clickFocusRing(at index: Int, in root: NSView) -> Bool {
        guard let split = splitViews(in: root).first, let pane = split.subviews.first else { return false }
        let rings = views(in: pane).filter { view in
            String(describing: type(of: view)).contains("FocusRing")
                && view.bounds.width > 20
                && view.bounds.height > 8
                && view.isHiddenOrHasHiddenAncestor == false
        }.sorted { $0.frame.minX < $1.frame.minX }
        guard rings.indices.contains(index) else { return false }
        let ring = rings[index]
        let point = ring.convert(NSPoint(x: ring.bounds.midX, y: ring.bounds.midY), to: nil)
        return click(windowPoint: point)
    }

    @discardableResult
    func click(windowPoint: NSPoint) -> Bool {
        let ignoredMouseEvents = window.ignoresMouseEvents
        window.ignoresMouseEvents = false
        defer { window.ignoresMouseEvents = ignoredMouseEvents }
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: windowPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return false }
        window.sendEvent(down)
        window.sendEvent(up)
        return true
    }

    @discardableResult
    func pressControl(containing needle: String, in root: NSView) -> Bool {
        let matches = visibleNodes(in: root).filter { node in
            controlText(of: node).joined(separator: " ").localizedCaseInsensitiveContains(needle)
        }
        let ordered = matches.sorted { nodeArea($0) < nodeArea($1) }
        return ordered.contains { invokePress(on: $0) }
    }

    func editableBoatField(in root: NSView) -> NSTextField? {
        textFields(in: root).first { field in
            field.bounds.width > 20 && field.bounds.height > 8 && field.stringValue == "Mainsail 1"
        }
    }

    func revealBoatEditor() {
        guard let boatHost = destinationHost(.boat) else { return }
        for scroll in scrollViews(in: boatHost) where scroll.bounds.width > 200 {
            let height = scroll.documentView?.bounds.height ?? 0
            let viewport = scroll.contentView.bounds.height
            let target = max(0, height - viewport)
            guard target > 20 else { continue }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        }
    }

    private func visibleNodes(in root: NSView) -> [NSObject] {
        var nodes: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            if let view = node as? NSView {
                guard view.isHiddenOrHasHiddenAncestor == false, view.bounds.width > 2, view.bounds.height > 2 else { return }
            }
            nodes.append(node)
            for child in controlChildren(of: node) {
                visit(child)
            }
        }
        visit(root)
        return nodes
    }

    private func controlChildren(of node: NSObject) -> [NSObject] {
        var children: [NSObject] = []
        if let view = node as? NSView {
            children.append(contentsOf: view.subviews)
            for child in view.accessibilityChildren() ?? [] {
                guard let object = child as? NSObject, !children.contains(where: { $0 === object }) else { continue }
                children.append(object)
            }
        }
        let selector = NSSelectorFromString("accessibilityChildren")
        if node.responds(to: selector),
           let value = node.perform(selector)?.takeUnretainedValue() as? [Any] {
            for child in value {
                guard let object = child as? NSObject, !children.contains(where: { $0 === object }) else { continue }
                children.append(object)
            }
        }
        return children
    }

    private func controlText(of node: NSObject) -> [String] {
        var texts: [String] = []
        if let field = node as? NSTextField { texts.append(field.stringValue) }
        if let text = node as? NSTextView { texts.append(text.string) }
        if let button = node as? NSButton {
            texts.append(button.title)
            texts.append(button.attributedTitle.string)
        }
        if let view = node as? NSView {
            texts.append(contentsOf: [view.toolTip, view.accessibilityLabel(), view.accessibilityHelp(), view.accessibilityIdentifier()].compactMap { $0 })
        }
        if let element = node as? NSAccessibilityElement {
            texts.append(contentsOf: [
                element.accessibilityTitle(),
                element.accessibilityLabel(),
                element.accessibilityHelp(),
                element.accessibilityIdentifier(),
                element.accessibilityValue() as? String
            ].compactMap { $0 })
        }
        for name in ["accessibilityLabel", "accessibilityHelp", "accessibilityIdentifier", "accessibilityTitle"] {
            if let text = axString(name, on: node) { texts.append(text) }
        }
        for attr in [
            NSAccessibility.Attribute.title.rawValue,
            NSAccessibility.Attribute.description.rawValue,
            NSAccessibility.Attribute.help.rawValue,
            NSAccessibility.Attribute.identifier.rawValue,
            NSAccessibility.Attribute.value.rawValue,
            "AXLabel"
        ] {
            if let text = axAttribute(attr, on: node) { texts.append(text) }
        }
        return texts
    }

    private func axAttribute(_ attribute: String, on object: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector, with: attribute)?.takeUnretainedValue() as? String
    }

    private func axString(_ name: String, on object: NSObject) -> String? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    private func invokePress(on object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let implementation = unsafeBitCast(object.method(for: selector), to: Press.self)
        return implementation(object, selector)
    }

    private func nodeArea(_ node: NSObject) -> CGFloat {
        guard let view = node as? NSView else { return .greatestFiniteMagnitude }
        return view.bounds.width * view.bounds.height
    }

    func layoutPage(windowSize: NSSize, sidebar: CGFloat) {
        window.setContentSize(windowSize)
        if let content = window.contentView {
            host.frame = content.bounds
        }
        host.layoutSubtreeIfNeeded()
        let splits = views(in: host).compactMap { $0 as? NSSplitView }.filter { $0.bounds.width > 400 }
        if let split = splits.max(by: { $0.bounds.width < $1.bounds.width }) {
            split.setPosition(sidebar, ofDividerAt: 0)
        }
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
    }

    func simulationScroll() -> NSScrollView? {
        guard let root = destinationHost(.simulation) else { return nil }
        return scrollViews(in: root).first { $0.bounds.width > 200 && $0.bounds.height > 80 }
    }

    /// Width proposed to the setup body: the scroll viewport after the page inset, capped by the page max.
    func setupContentWidth() -> CGFloat? {
        guard let scroll = simulationScroll() else { return nil }
        let viewport = scroll.contentView.bounds.width
        guard viewport > 40 else { return nil }
        return min(viewport, ResponsiveLayout.adaptivePageMaxWidth) - PageChrome.padding * 2
    }

    func revealSensors() -> NSView? {
        guard let heading = sensorField("Onboard Sensors") else { return nil }
        heading.scrollToVisible(heading.bounds)
        if let scroll = heading.enclosingScrollView {
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        host.layoutSubtreeIfNeeded()
        return heading
    }

    /// The text itself, not an ancestor that merely contains the title in a descendant.
    func sensorField(_ title: String) -> NSView? {
        guard let document = simulationScroll()?.documentView else { return nil }
        var best: NSView?
        var seen = Set<ObjectIdentifier>()
        func consider(_ view: NSView) {
            guard view.isHiddenOrHasHiddenAncestor == false,
                  view.bounds.width > 8,
                  view.bounds.height > 8,
                  view.bounds.height < 80 else { return }
            let area = view.bounds.width * view.bounds.height
            let bestArea = best.map { $0.bounds.width * $0.bounds.height } ?? .greatestFiniteMagnitude
            if area < bestArea { best = view }
        }
        func visit(_ node: NSObject, nearest: NSView) {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            var texts = controlText(of: node)
            if let value = axString("accessibilityValue", on: node) { texts.append(value) }
            if texts.contains(title) {
                consider((node as? NSView) ?? nearest)
            }
            if let view = node as? NSView, view.isHiddenOrHasHiddenAncestor || view.bounds.width <= 1 || view.bounds.height <= 1 {
                return
            }
            let next = (node as? NSView) ?? nearest
            for child in controlChildren(of: node) {
                visit(child, nearest: next)
            }
        }
        visit(document, nearest: document)
        return best
    }

    func sensorsAreReachable() -> Bool {
        guard let heading = sensorField("Onboard Sensors"),
              let anemometer = sensorField("Anemometer"),
              let gps = sensorField("GPS"),
              let scroll = simulationScroll(),
              let document = scroll.documentView else { return false }
        for field in [heading, anemometer, gps] {
            let frame = field.convert(field.bounds, to: document)
            guard frame.width > 8, frame.height > 8, document.bounds.intersects(frame) else { return false }
        }
        gps.scrollToVisible(gps.bounds)
        scroll.reflectScrolledClipView(scroll.contentView)
        let visible = gps.convert(gps.bounds, to: scroll.contentView)
        return scroll.contentView.bounds.intersects(visible)
    }

    func sensorReport() -> String {
        func size(_ title: String) -> String {
            guard let field = sensorField(title) else { return "\(title)=missing" }
            return "\(title)=\(Int(field.bounds.width))x\(Int(field.bounds.height))"
        }
        let width = setupContentWidth().map { Int($0) } ?? -1
        let document = simulationScroll()?.documentView?.bounds.height
        let text = destinationHost(.simulation).map { strings(in: $0).filter { $0.count > 2 && $0.count < 40 }.prefix(24).joined(separator: "|") } ?? ""
        return "\(size("Onboard Sensors")) \(size("Anemometer")) \(size("GPS")) content=\(width) document=\(document.map { Int($0) } ?? -1) \(text) \(describe())"
    }

    @discardableResult
    func selectLibraryRow(named name: String, in root: NSView) -> Bool {
        guard let table = libraryTable(in: root), let row = libraryRowIndex(named: name, table: table) else { return false }
        table.scrollRowToVisible(row)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        NotificationCenter.default.post(name: NSTableView.selectionDidChangeNotification, object: table)
        if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) {
            let point = cell.convert(NSPoint(x: min(24, max(4, cell.bounds.midX)), y: cell.bounds.midY), to: nil)
            _ = click(windowPoint: point)
        }
        return true
    }

    private func libraryRowIndex(named name: String, table: NSTableView) -> Int? {
        for row in 0..<table.numberOfRows where libraryRowText(table, row: row).localizedCaseInsensitiveContains(name) {
            return row
        }
        switch name {
        case "Extasy":
            return table.numberOfRows > 0 ? 0 : nil
        case "Nimana":
            return table.numberOfRows > 1 ? 1 : nil
        case "Custom Vessel":
            return table.numberOfRows > 2 ? table.numberOfRows - 1 : nil
        default:
            return nil
        }
    }

    private func libraryRowText(_ table: NSTableView, row: Int) -> String {
        var parts: [String] = []
        if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) {
            parts.append(contentsOf: strings(in: cell))
            parts.append(cell.accessibilityLabel() ?? "")
        }
        if let rowView = table.rowView(atRow: row, makeIfNecessary: true) {
            parts.append(contentsOf: strings(in: rowView))
            parts.append(rowView.accessibilityLabel() ?? "")
        }
        return parts.joined(separator: " ")
    }

    func detailShows(_ markers: [String], in root: NSView) -> Bool {
        let text = detailText(in: root).joined(separator: "\n")
        return markers.allSatisfy { text.contains($0) }
    }

    func detailLacks(_ markers: [String], in root: NSView) -> Bool {
        let text = detailText(in: root).joined(separator: "\n")
        return markers.allSatisfy { text.contains($0) == false }
    }

    func detailReport() -> String {
        let session = sessionMarker()?.session
        let detail = destinationHost(.boat).map {
            detailText(in: $0).filter { $0.count > 2 && $0.count < 60 }.prefix(16).joined(separator: "|")
        } ?? ""
        return "id=\(session?.highlightedID?.uuidString ?? "nil") buffer=\(session?.buffer.name ?? "nil") \(detail) \(describe())"
    }

    private func libraryTable(in root: NSView) -> NSTableView? {
        tables(in: root).first { table in
            table.bounds.width > 160
                && table.bounds.width < 420
                && table.isHiddenOrHasHiddenAncestor == false
        }
    }

    private func detailText(in root: NSView) -> [String] {
        guard let table = libraryTable(in: root) else { return [] }
        let minX = table.convert(table.bounds, to: nil).maxX - 1
        return views(in: root).filter { view in
            view.isHiddenOrHasHiddenAncestor == false
                && view.bounds.width > 2
                && view.bounds.height > 2
                && view.convert(view.bounds, to: nil).minX >= minX
        }.flatMap { strings(in: $0) }
    }

    private func strings(in root: NSObject) -> [String] {
        var texts: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            if let view = node as? NSView {
                guard view.isHiddenOrHasHiddenAncestor == false, view.bounds.width > 1, view.bounds.height > 1 else { return }
            }
            texts.append(contentsOf: controlText(of: node))
            if let value = axString("accessibilityValue", on: node) {
                texts.append(value)
            }
            for child in controlChildren(of: node) {
                visit(child)
            }
        }
        visit(root)
        return texts
    }

    func describe() -> String {
        let markers = markers().map { marker in
            let scroll = marker.enclosingScrollView
            let anchors = scroll.map { boundAnchors(in: $0).count } ?? -1
            return "\(marker.page.rawValue) anchors \(anchors) \(chain(from: marker))"
        }
        let consoles = consoleHosts().map { "console \($0.bounds.size)" }
        let maps = mapHosts().map { "map \($0.bounds.size)" }
        let searches = manualSearchFields().map { _ in "manual-search" }
        let labels = visibleNodes(in: host).flatMap { controlText(of: $0) }.filter { $0.count > 2 && $0.count < 80 }
        var unique: [String] = []
        for label in labels where unique.contains(label) == false && unique.count < 8 {
            unique.append(label)
        }
        return (markers + consoles + maps + searches + unique).joined(separator: "; ")
    }

    private func chain(from view: NSView) -> String {
        var parts: [String] = []
        var current: NSView? = view
        var hops = 0
        while let node = current, hops < 7 {
            parts.append("\(type(of: node)) \(Int(node.bounds.width))x\(Int(node.bounds.height))")
            current = node.superview
            hops += 1
        }
        return parts.joined(separator: " > ")
    }

    private func views(in root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + views(in: $0) }
    }
}

private final class CountingVesselProfileStore: VesselProfileStoring {
    private(set) var document: VesselProfileDocument?
    private(set) var saveCount = 0

    func loadDocument() throws -> VesselProfileDocument? { document }

    func saveDocument(_ document: VesselProfileDocument) throws {
        saveCount += 1
        self.document = document
    }
}
