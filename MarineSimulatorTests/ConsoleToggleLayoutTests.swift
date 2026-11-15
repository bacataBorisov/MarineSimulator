import AppKit
import MapKit
import QuartzCore
import SwiftUI
import Testing
@testable import MarineSimulator

@_silgen_name("MarineCatchException")
private func MarineCatchException(_ body: @convention(block) () -> Void) -> NSException?

/// Hosts the real Manual column. A model of the height binding does not prove AppKit
/// will finish its constraint passes, so this test lays that window out.
@Suite
@MainActor
struct ConsoleToggleLayoutTests {

    @Test(.timeLimit(.minutes(2)))
    func rapidManualTogglesParkAndLeaveThePageOffset() throws {
        let suite = "ConsoleToggleLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(SidebarItem.manual.rawValue, forKey: "main_view.selection")
        defaults.set(220.0, forKey: ConsoleHeightStorage.key)
        defaults.set(220.0, forKey: "console_panel.last_expanded_height")

        let standardKeys = [
            ConsoleHeightStorage.key,
            "console_panel.last_expanded_height",
            "main_view.selection",
        ]
        let standardSnapshot = standardKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let simulator = NMEASimulator(userDefaults: defaults)
        let host = NSHostingView(rootView: MainView(nmeaManager: simulator).defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.contentView = host
        host.autoresizingMask = [.width, .height]
        defer {
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

        window.orderFrontRegardless()
        let ready = waitUntil(host: host) {
            guard hasManualColumns(host), consoleHosts(in: host).count == 1 else { return false }
            guard logHeight(in: host) >= 140 else { return false }
            return !stableTargets(in: host).isEmpty
        }
        try #require(ready, "Manual console did not lay out: \(describe(host))")
        #expect(largeMapViews(in: host).isEmpty, "Manual laid out a full-size map: \(describe(host))")

        let targets = stableTargets(in: host)
        for target in targets {
            guard let scroll = match(target, in: pageScrollViews(in: host)) else { continue }
            scrollTo(scroll.scroll, y: target.offset)
        }
        let held = waitUntil(host: host, timeout: 1) {
            targets.allSatisfy { target in
                guard let scroll = match(target, in: pageScrollViews(in: host)) else { return false }
                return abs(scroll.offset - target.offset) < 2
            }
        }
        try #require(held, "Manual did not keep a mid-page offset: \(describeScrolls(host))")

        let expandedBeforeDrag = logHeight(in: host)
        let handle = try #require(resizeHandles(in: host).max { $0.bounds.height < $1.bounds.height })
        handle.mouseDown(with: try mouseEvent(.leftMouseDown, y: 400, window: window, number: 1))
        handle.mouseDragged(with: try mouseEvent(.leftMouseDragged, y: 424, window: window, number: 2))
        let dragged = waitUntil(host: host, timeout: 0.4) {
            abs(logHeight(in: host) - expandedBeforeDrag) > 12
        }
        try #require(dragged, "resize handle did not change the console height from \(expandedBeforeDrag)")
        let offsetAfterDrag = targets.compactMap { match($0, in: pageScrollViews(in: host)) }

        try pressToggle("Hide Console", in: host)
        let collapsed = waitUntil(host: host, timeout: 0.25) {
            logHeight(in: host) <= 1 && storedHeight(defaults) <= 0.5
        }
        try #require(collapsed, "toggle did not park the console shut: height \(logHeight(in: host)) stored \(storedHeight(defaults))")
        forceLayouts(host, times: 8)
        try assertOffsetsUnchanged(offsetAfterDrag, in: host, tolerance: 8)
        handle.mouseUp(with: try mouseEvent(.leftMouseUp, y: 424, window: window, number: 3))
        forceLayouts(host, times: 4)
        #expect(logHeight(in: host) <= 1, "mouse-up reopened a drag the toggle had cancelled")
        try assertOffsetsUnchanged(offsetAfterDrag, in: host, tolerance: 8)

        let parkedBaseline = targets.compactMap { match($0, in: pageScrollViews(in: host)) }
        for index in 0..<8 {
            let wantExpanded = index % 2 == 0
            let before = logHeight(in: host)
            for candidate in resizeHandles(in: host) {
                candidate.mouseDown(with: try mouseEvent(.leftMouseDown, y: 300, window: window, number: 10 + index))
                candidate.mouseUp(with: try mouseEvent(.leftMouseUp, y: 300, window: window, number: 30 + index))
            }
            forceLayouts(host, times: 2)
            #expect(abs(logHeight(in: host) - before) < 1, "a toolbar click without movement resized the console")

            try pressToggle(wantExpanded ? "Show Console" : "Hide Console", in: host)
            let parked = waitUntil(host: host, timeout: 0.25) {
                parkedConsole(expanded: wantExpanded, in: host, defaults: defaults)
            }
            try #require(
                parked,
                "toggle \(index) did not park \(wantExpanded ? "open" : "shut"): height \(logHeight(in: host)) stored \(storedHeight(defaults)) \(describe(host))"
            )
            forceLayouts(host, times: 6)
            #expect(
                parkedConsole(expanded: wantExpanded, in: host, defaults: defaults),
                "further layout passes left the console between parked heights"
            )
            #expect(abs(logHeight(in: host) - before) > 100, "toggle \(index) overlapped the previous height")
            #expect(consoleHosts(in: host).count == 1)
        }

        try assertOffsetsUnchanged(parkedBaseline, in: host, tolerance: 8)
        #expect(consoleHosts(in: host).count == 1)
        #expect(largeMapViews(in: host).isEmpty, "console toggles laid out a full-size map")
        #expect(hasManualColumns(host))
    }

    /// Presses are back-to-back. Waiting for each toggle to park hid the constraint loop.
    @Test(.timeLimit(.minutes(2)))
    func backToBackManualTogglesDoNotExceedConstraintPasses() throws {
        let harness = try ManualWindowHarness()
        defer { harness.close() }
        let host = harness.host
        let ready = harness.waitUntil {
            hasManualColumns(host) && consoleHosts(in: host).count == 1 && logHeight(in: host) >= 140
        }
        try #require(ready, "Manual did not lay out: \(describe(host))")
        let toggle = try #require(consoleToggleButton(in: host))

        let storm = MarineCatchException {
            for _ in 0..<40 {
                _ = self.invokePress(on: toggle)
                host.needsUpdateConstraints = true
                host.updateConstraintsForSubtreeIfNeeded()
                host.layoutSubtreeIfNeeded()
            }
            for _ in 0..<25 {
                CATransaction.flush()
                host.needsUpdateConstraints = true
                host.updateConstraintsForSubtreeIfNeeded()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
        }
        #expect(storm == nil, "constraint loop: \(storm?.reason ?? "")")

        let zeroMaps = mapKitViews(in: host).filter { $0.bounds.width <= 1 || $0.bounds.height <= 1 }
        #expect(zeroMaps.isEmpty, "a zero-size map is still in the window: \(zeroMaps.map(\.bounds))")
        #expect(mapHosts(in: host).count == 1, "dashboard map host was not retained")
        #expect(consoleHosts(in: host).count == 1)
        #expect(hasManualColumns(host), "Manual columns did not survive the burst: \(describe(host))")
    }

    /// Same burst with no retained dashboard. The console path itself must stay stable.
    @Test(.timeLimit(.minutes(2)))
    func backToBackTogglesWithoutTheRetainedDashboardStayStable() throws {
        let suite = "ConsoleToggleLayoutTests.shell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults)
        let host = NSHostingView(
            rootView: ManualShellColumn(simulator: simulator).defaultAppStorage(defaults)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.autoresizingMask = [.width, .height]
        defer {
            window.orderOut(nil)
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
        window.makeKeyAndOrderFront(nil)
        let ready = waitUntil(host: host) {
            hasManualColumns(host) && consoleHosts(in: host).count == 1 && logHeight(in: host) >= 140
        }
        try #require(ready, "shell Manual did not lay out: \(describe(host))")
        #expect(mapKitViews(in: host).isEmpty)
        #expect(!views(in: host).contains { $0 is NSSplitView }, "Manual still installed a split view")
        let toggle = try #require(consoleToggleButton(in: host))
        let storm = MarineCatchException {
            for _ in 0..<40 {
                _ = self.invokePress(on: toggle)
                host.needsUpdateConstraints = true
                host.updateConstraintsForSubtreeIfNeeded()
                host.layoutSubtreeIfNeeded()
            }
            for _ in 0..<25 {
                CATransaction.flush()
                host.needsUpdateConstraints = true
                host.updateConstraintsForSubtreeIfNeeded()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
        }
        #expect(storm == nil, "shell constraint loop: \(storm?.reason ?? "")")
        #expect(consoleHosts(in: host).count == 1)
        #expect(mapKitViews(in: host).isEmpty)
        #expect(hasManualColumns(host), "Manual columns did not survive the shell burst: \(describe(host))")
        #expect(!views(in: host).contains { $0 is NSSplitView })
    }

    private func pressToggle(_ label: String, in root: NSView) throws {
        let control = try #require(consoleToggleButton(in: root), "Missing \(label) control")
        if let button = control as? NSButton {
            button.performClick(nil)
            return
        }
        if let view = control as? NSView, view.accessibilityPerformPress() { return }
        try #require(invokePress(on: control))
    }

    /// The show/hide control is the SwiftUI button immediately before the console-mode picker.
    private func consoleToggleButton(in root: NSView) -> NSObject? {
        var parentOf: [ObjectIdentifier: NSObject] = [:]
        var seen = Set<ObjectIdentifier>()
        var modeSegment: NSObject?
        func walk(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if modeSegment == nil, controlText(of: object).contains("NMEA") {
                modeSegment = object
            }
            for child in controlChildren(of: object) {
                parentOf[ObjectIdentifier(child)] = object
                walk(child)
            }
        }
        walk(root)
        guard let modeSegment else { return nil }

        func containsModeSegment(_ object: NSObject, visiting: inout Set<ObjectIdentifier>) -> Bool {
            guard visiting.insert(ObjectIdentifier(object)).inserted else { return false }
            if controlText(of: object).contains("NMEA") { return true }
            return controlChildren(of: object).contains { containsModeSegment($0, visiting: &visiting) }
        }

        var node = parentOf[ObjectIdentifier(modeSegment)]
        while let current = node {
            let children = controlChildren(of: current)
            if let pickerIndex = children.firstIndex(where: { child in
                var visiting: Set<ObjectIdentifier> = []
                return containsModeSegment(child, visiting: &visiting)
            }) {
                let toggle = children[..<pickerIndex].last {
                    String(describing: type(of: $0)).contains("SwiftUIAppKitButton")
                }
                if let toggle { return toggle }
            }
            node = parentOf[ObjectIdentifier(current)]
        }
        return nil
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
        if let view = node as? NSView {
            texts.append(contentsOf: [view.toolTip, view.accessibilityLabel(), view.accessibilityHelp(), view.accessibilityIdentifier()].compactMap { $0 })
        }
        for name in ["accessibilityLabel", "accessibilityHelp", "accessibilityIdentifier", "accessibilityTitle", "accessibilityRole"] {
            if let text = axString(name, on: node) { texts.append(text) }
        }
        return texts
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

    private func parkedConsole(expanded: Bool, in root: NSView, defaults: UserDefaults) -> Bool {
        let height = logHeight(in: root)
        let stored = storedHeight(defaults)
        if expanded {
            return height >= 140 && stored >= 140
        }
        return height <= 1 && stored <= 0.5
    }

    private func assertOffsetsUnchanged(_ before: [PageScrollSample], in root: NSView, tolerance: CGFloat) throws {
        let after = pageScrollViews(in: root)
        try #require(!before.isEmpty)
        for sample in before {
            let match = after.min { lhs, rhs in
                abs(lhs.width - sample.width) + abs(lhs.documentHeight - sample.documentHeight)
                    < abs(rhs.width - sample.width) + abs(rhs.documentHeight - sample.documentHeight)
            }
            let matched = try #require(match)
            #expect(
                abs(matched.width - sample.width) < 40,
                "page scroller disappeared (width \(sample.width), document \(sample.documentHeight))"
            )
            #expect(
                abs(matched.offset - sample.offset) < tolerance,
                "page offset moved from \(sample.offset) to \(matched.offset) while the console toggled"
            )
        }
    }

    private func storedHeight(_ defaults: UserDefaults) -> Double {
        defaults.double(forKey: ConsoleHeightStorage.key)
    }

    private func scrollTo(_ scroll: NSScrollView, y: CGFloat) {
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        var origin = clip.bounds.origin
        origin.y = y
        clip.scroll(to: origin)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
    }

    private func forceLayouts(_ root: NSView, times: Int) {
        for _ in 0..<times {
            CATransaction.flush()
            root.needsLayout = true
            root.needsUpdateConstraints = true
            root.layoutSubtreeIfNeeded()
        }
    }

    @discardableResult
    private func waitUntil(host: NSView, timeout: TimeInterval = 5, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            forceLayouts(host, times: 1)
            if predicate() { return true }
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        y: CGFloat,
        window: NSWindow,
        number: Int
    ) throws -> NSEvent {
        let event = NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 40, y: y),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: number,
            clickCount: 1,
            pressure: 1
        )
        return try #require(event)
    }

    /// The search field sits in the fixed topics column. The selected topic is the pane to its right.
    private func hasManualColumns(_ root: NSView) -> Bool {
        guard let search = manualSearchFields(in: root).first else { return false }
        let searchFrame = search.convert(search.bounds, to: nil)
        guard let columns = manualColumns(in: root) else { return false }
        let columnSpan = columns.body.minX - searchFrame.minX
        return searchFrame.width > 160
            && columnSpan >= 200
            && columnSpan <= 360
            && columns.topics.height > 160
            && columns.body.height > 160
            && columns.body.width > searchFrame.width
    }

    private func manualColumns(in root: NSView) -> (topics: NSRect, body: NSRect)? {
        guard let search = manualSearchFields(in: root).first else { return nil }
        let searchFrame = search.convert(search.bounds, to: nil)
        let scrolls = pageScrollViews(in: root).map { sample in
            sample.scroll.convert(sample.scroll.bounds, to: nil)
        }
        let topicCandidates = scrolls.filter { frame in
            frame.maxX > searchFrame.minX + 8
                && frame.minX < searchFrame.maxX
                && frame.height > 160
                && frame.maxY <= searchFrame.maxY + 8
                && frame.width > 160
        }
        guard let topics = topicCandidates.max(by: { $0.height < $1.height }) else { return nil }
        let bodyCandidates = scrolls.filter { frame in
            frame.minX >= searchFrame.maxX - 8
                && abs(frame.minX - topics.maxX) < 24
                && frame.width > searchFrame.width
                && frame.height > 160
        }
        guard let body = bodyCandidates.max(by: { $0.width < $1.width }) else { return nil }
        return (topics, body)
    }

    private func manualSearchFields(in root: NSView) -> [NSView] {
        views(in: root).filter { view in
            if let field = view as? NSTextField {
                let placeholder = field.placeholderString ?? field.placeholderAttributedString?.string ?? ""
                if placeholder.localizedCaseInsensitiveContains("search manual") { return true }
            }
            return controlText(of: view).joined(separator: " ").localizedCaseInsensitiveContains("search manual")
        }
    }

    private func logHeight(in root: NSView) -> CGFloat {
        consoleHosts(in: root).map(\.bounds.height).max() ?? 0
    }

    private func consoleHosts(in root: NSView) -> [NSView] {
        views(in: root).filter { String(describing: type(of: $0)).contains("ConsoleLogHost") }
    }

    private func resizeHandles(in root: NSView) -> [NSView] {
        views(in: root).filter { view in
            String(describing: type(of: view)).contains("ConsoleResizeHandleView") && view.bounds.height > 2
        }
    }

    /// A document offset that stays legal while the console drag and toggle resize this scroller.
    private func stableTargets(in root: NSView) -> [PageScrollSample] {
        pageScrollViews(in: root).compactMap { sample in
            let clip = sample.scroll.contentView
            let shorter = ConsoleScrollLimits.reading(
                clip,
                viewportHeight: max(80, sample.viewportHeight - 40)
            )
            let taller = ConsoleScrollLimits.reading(
                clip,
                viewportHeight: sample.viewportHeight + 230
            )
            let floor = max(shorter.minimum, taller.minimum)
            let ceiling = min(shorter.maximum, taller.maximum)
            let target = min(ceiling - 8, max(floor + 8, 32))
            guard target > floor + 4, target < ceiling - 4 else { return nil }
            var parked = sample
            parked.offset = target
            return parked
        }
    }

    private func match(_ target: PageScrollSample, in samples: [PageScrollSample]) -> PageScrollSample? {
        samples.min { lhs, rhs in
            abs(lhs.width - target.width) + abs(lhs.documentHeight - target.documentHeight)
                < abs(rhs.width - target.width) + abs(rhs.documentHeight - target.documentHeight)
        }
    }

    private func pageScrollViews(in root: NSView) -> [PageScrollSample] {
        let consoles = consoleHosts(in: root)
        return views(in: root).compactMap { view in
            guard let scroll = view as? NSScrollView else { return nil }
            if consoles.contains(where: { scroll.isDescendant(of: $0) || $0.isDescendant(of: scroll) }) {
                return nil
            }
            guard scroll.bounds.width > 120, scroll.bounds.height > 80 else { return nil }
            let document = scroll.documentView?.bounds.height ?? 0
            guard document > 1 else { return nil }
            return PageScrollSample(
                scroll: scroll,
                width: scroll.bounds.width,
                documentHeight: document,
                viewportHeight: scroll.contentView.bounds.height,
                offset: scroll.contentView.bounds.origin.y
            )
        }
    }

    private func mapKitViews(in root: NSView) -> [MKMapView] {
        views(in: root).compactMap { $0 as? MKMapView }
    }

    private func mapHosts(in root: NSView) -> [BoatMapContainerView] {
        views(in: root).compactMap { $0 as? BoatMapContainerView }
    }

    private func largeMapViews(in root: NSView) -> [MKMapView] {
        views(in: root).compactMap { view in
            guard let map = view as? MKMapView,
                  !map.isHiddenOrHasHiddenAncestor,
                  map.bounds.width > 2,
                  map.bounds.height > 2 else { return nil }
            return map
        }
    }

    private func views(in root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + views(in: $0) }
    }

    private func describe(_ root: NSView) -> String {
        let consoles = consoleHosts(in: root).map { "console \($0.bounds.size)" }
        let maps = largeMapViews(in: root).map { "map \($0.bounds.size)" }
        let columns = manualColumns(in: root).map {
            "topics \(rect($0.topics)) body \(rect($0.body))"
        }
        let searches = manualSearchFields(in: root).map { view in
            "search \(rect(view.convert(view.bounds, to: nil)))"
        }
        return (consoles + maps + (columns.map { [$0] } ?? []) + searches + describeScrolls(root)).joined(separator: "; ")
    }

    private func rect(_ frame: NSRect) -> String {
        "x \(frame.minX) y \(frame.minY) \(frame.width)x\(frame.height)"
    }

    private func describeScrolls(_ root: NSView) -> [String] {
        pageScrollViews(in: root).map {
            let frame = $0.scroll.convert($0.scroll.bounds, to: nil)
            return "scroll x \(frame.minX) \(frame.width)x\($0.viewportHeight) doc \($0.documentHeight) y \($0.offset)"
        }
    }
}

private struct ManualShellColumn: View {
    var simulator: NMEASimulator
    @State private var consoleHeight = CGFloat(220)

    var body: some View {
        VStack(spacing: 0) {
            ManualView()
                .environment(\.pageScrollIdentity, .manual)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ConsolePanelView(
                nmeaManager: simulator,
                consoleHeight: $consoleHeight,
                geometryHeight: 760
            )
        }
        .environment(simulator)
    }
}

@MainActor
private final class ManualWindowHarness {
    let host: NSView
    private let window: NSWindow
    private let defaults: UserDefaults
    private let suite: String
    private let standardSnapshot: [(String, Any?)]

    init() throws {
        suite = "ConsoleToggleLayoutTests.burst.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(SidebarItem.manual.rawValue, forKey: "main_view.selection")
        defaults.set(220.0, forKey: ConsoleHeightStorage.key)
        defaults.set(220.0, forKey: "console_panel.last_expanded_height")
        self.defaults = defaults
        standardSnapshot = [
            ConsoleHeightStorage.key,
            "console_panel.last_expanded_height",
            "main_view.selection",
        ].map { ($0, UserDefaults.standard.object(forKey: $0)) }

        let simulator = NMEASimulator(userDefaults: defaults)
        let root = NSHostingView(rootView: MainView(nmeaManager: simulator).defaultAppStorage(defaults))
        host = root
        window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = root
        root.autoresizingMask = [.width, .height]
        window.makeKeyAndOrderFront(nil)
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

    func waitUntil(timeout: TimeInterval = 5, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            CATransaction.flush()
            host.layoutSubtreeIfNeeded()
            if predicate() { return true }
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

private struct PageScrollSample {
    var scroll: NSScrollView
    var width: CGFloat
    var documentHeight: CGFloat
    var viewportHeight: CGFloat
    var offset: CGFloat
}
