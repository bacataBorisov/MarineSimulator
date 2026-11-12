import AppKit
import MapKit
import QuartzCore
import SwiftUI
import Testing
@testable import MarineSimulator

@Suite
@MainActor
struct DashboardDetailLayoutTests {

    @Test
    func theRetainedDashboardFillsOnlyTheDashboard() {
        let detail = CGSize(width: 960, height: 640)
        #expect(SidebarItem.dashboard.retainedDashboardSize(fitting: detail) == detail)
        #expect(SidebarItem.dashboard.placesConsoleInTheShell == false)

        let pages: [SidebarItem] = [
            .connection, .simulation, .boat, .diagnostics, .manual,
            .wind, .compass, .hydro, .gps
        ]
        for page in pages {
            let size = page.retainedDashboardSize(fitting: detail)
            #expect(size == .zero)
            #expect(page.placesConsoleInTheShell)
        }
    }

    /// Mounts the real detail column. A non-dashboard page must not keep the dashboard
    /// map at the detail size, and returning must reuse that same map host.
    @Test(.timeLimit(.minutes(2)))
    func leavingTheDashboardCollapsesItsMapAndReturningKeepsTheSameHost() throws {
        let suite = "DashboardDetailLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(SidebarItem.dashboard.rawValue, forKey: "main_view.selection")
        defaults.set(200.0, forKey: ConsoleHeightStorage.key)

        let standardConsoleHeight = UserDefaults.standard.object(forKey: ConsoleHeightStorage.key)
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
            if let standardConsoleHeight {
                UserDefaults.standard.set(standardConsoleHeight, forKey: ConsoleHeightStorage.key)
            } else {
                UserDefaults.standard.removeObject(forKey: ConsoleHeightStorage.key)
            }
            #if DEBUG
            ScrollRuntimeTrace.shared.resetForTest()
            #endif
        }

        window.orderFrontRegardless()
        let appeared = waitUntil(host: host) {
            let maps = mapHosts(in: host)
            return maps.count == 1 && maps[0].bounds.width > 400 && maps[0].bounds.height > 300
        }
        try #require(appeared, "dashboard map did not fill the detail column: \(describe(host))")

        let dashboardMap = mapHosts(in: host)[0]
        let retainedMapKit = try #require(mapKitViews(in: host).first, "dashboard did not attach its map: \(describe(host))")
        let dashboardConsoleCount = consoleHosts(in: host).count
        #expect(dashboardConsoleCount == 1, "dashboard consoles: \(dashboardConsoleCount) \(describe(host))")

        select(.connection, defaults: defaults, host: host)
        let hidden = waitUntil(host: host) {
            let maps = mapHosts(in: host)
            guard maps.count == 1, maps[0] === dashboardMap else { return false }
            return maps[0].bounds.width <= 1 && maps[0].bounds.height <= 1
        }
        try #require(hidden, "connection still lays the dashboard map out at \(dashboardMap.bounds) \(describe(host))")
        #expect(consoleHosts(in: host).count == 1, "connection consoles: \(describe(host))")
        #expect(largeMapViews(in: host).isEmpty, "a full-size map is still in the connection column: \(describe(host))")
        #expect(mapKitViews(in: host).isEmpty, "the retained map stayed in the window at connection: \(describe(host))")

        select(.simulation, defaults: defaults, host: host)
        let stillHidden = waitUntil(host: host) {
            let maps = mapHosts(in: host)
            guard maps.count == 1, maps[0] === dashboardMap else { return false }
            return maps[0].bounds.width <= 1 && maps[0].bounds.height <= 1
        }
        try #require(stillHidden, "simulation lays the dashboard map out at \(dashboardMap.bounds) \(describe(host))")
        #expect(consoleHosts(in: host).count == 1)

        select(.dashboard, defaults: defaults, host: host)
        let returned = waitUntil(host: host) {
            let maps = mapHosts(in: host)
            guard maps.count == 1, maps[0] === dashboardMap else { return false }
            return maps[0].bounds.width > 400 && maps[0].bounds.height > 300
        }
        try #require(returned, "returning created another map or left it collapsed: \(describe(host))")
        #expect(mapHosts(in: host)[0] === dashboardMap)
        #expect(mapKitViews(in: host).first === retainedMapKit, "returning created another MKMapView")
        #expect(consoleHosts(in: host).count == 1, "dashboard consoles after return: \(describe(host))")
    }

    private func select(_ item: SidebarItem, defaults: UserDefaults, host: NSView) {
        defaults.set(item.rawValue, forKey: "main_view.selection")
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
    }

    @discardableResult
    private func waitUntil(host: NSView, timeout: TimeInterval = 5, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            CATransaction.flush()
            host.layoutSubtreeIfNeeded()
            if predicate() { return true }
            if Date() >= deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func mapHosts(in root: NSView) -> [BoatMapContainerView] {
        views(in: root).compactMap { $0 as? BoatMapContainerView }
    }

    private func mapKitViews(in root: NSView) -> [MKMapView] {
        views(in: root).compactMap { $0 as? MKMapView }
    }

    private func largeMapViews(in root: NSView) -> [MKMapView] {
        views(in: root).compactMap { view in
            guard let map = view as? MKMapView, map.bounds.width > 2, map.bounds.height > 2 else { return nil }
            return map
        }
    }

    private func consoleHosts(in root: NSView) -> [NSView] {
        views(in: root).filter { String(describing: type(of: $0)).contains("ConsoleLogHost") }
    }

    private func views(in root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + views(in: $0) }
    }

    private func describe(_ root: NSView) -> String {
        let maps = mapHosts(in: root).map { "map \($0.bounds.size)" }
        let consoles = consoleHosts(in: root).map { "console \($0.bounds.size)" }
        let largeMaps = largeMapViews(in: root).map { "mk \($0.bounds.size)" }
        return (maps + consoles + largeMaps).joined(separator: "; ")
    }
}
