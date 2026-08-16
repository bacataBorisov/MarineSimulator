import SwiftUI
import Observation

/// Shared sidebar selection so sentence panels can deep-link to Setup pages.
@Observable
@MainActor
final class SidebarNavigation {
    var selectedItem: SidebarItem = .dashboard

    func select(_ item: SidebarItem) {
        selectedItem = item
    }
}

private struct SidebarNavigationKey: EnvironmentKey {
    static let defaultValue: SidebarNavigation? = nil
}

extension EnvironmentValues {
    var sidebarNavigation: SidebarNavigation? {
        get { self[SidebarNavigationKey.self] }
        set { self[SidebarNavigationKey.self] = newValue }
    }
}
