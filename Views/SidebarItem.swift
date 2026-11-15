import SwiftUI

enum SidebarItem: Hashable, CaseIterable {
    case gps, connection, simulation, diagnostics
    case sentencesOverview, wind, hydro, compass, boat
    case dashboard, manual

    /// Window toolbar title. Sidebar labels use the same strings.
    var pageTitle: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .connection: return "Connection"
        case .simulation: return "Simulation"
        case .boat: return "Boat Profile"
        case .diagnostics: return "Diagnostics"
        case .manual: return "Manual"
        case .sentencesOverview: return "Overview"
        case .wind: return "Wind"
        case .compass: return "Compass"
        case .hydro: return "Hydro"
        case .gps: return "GPS"
        }
    }
}

/// How a sidebar destination stays mounted.
/// The GPS map resource is named here and is not installed in this slice.
enum SidebarDestinationLifecycle: Equatable {
    /// Dashboard map host stays mounted and is proposed zero size off the dashboard.
    case retainedDashboardMap
    /// Complete page root stays in one stable AppKit host after the first visit.
    case retainedForm
    /// Complete page root and its one editor session stay in one stable AppKit host.
    case retainedSessionView
    /// A map resource may stay mounted while its page shell does not. Not installed yet.
    case retainedMapResource
    /// The switch creates the page and releases it on leave.
    case ephemeral
}

extension SidebarItem: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue {
        case "gps": self = .gps
        case "config", "connection": self = .connection
        case "simulation": self = .simulation
        case "sentencesOverview": self = .sentencesOverview
        case "wind": self = .wind
        case "hydro": self = .hydro
        case "compass": self = .compass
        case "boat": self = .boat
        case "diagnostics": self = .diagnostics
        case "dashboard": self = .dashboard
        case "manual": self = .manual
        default: return nil
        }
    }

    /// The dashboard draws its own console over the map. Every other page uses the shell column.
    var placesConsoleInTheShell: Bool {
        self != .dashboard
    }

    /// Stable AppKit root after the first visit. The GPS map resource is classified
    /// separately and is not mounted in this slice, so that page still leaves.
    var retainsDestinationTree: Bool {
        switch lifecycle {
        case .retainedForm, .retainedSessionView:
            return true
        case .retainedDashboardMap, .retainedMapResource, .ephemeral:
            return false
        }
    }

    /// Retention class for this destination. Dashboard keeps its existing map host.
    /// GPS names a map resource that this slice does not install.
    /// Manual stays ephemeral: parking its scrolled topics list asserts in SwiftUI.
    var lifecycle: SidebarDestinationLifecycle {
        switch self {
        case .dashboard:
            return .retainedDashboardMap
        case .connection, .simulation:
            return .retainedForm
        case .boat:
            return .retainedSessionView
        case .gps:
            return .retainedMapResource
        case .diagnostics, .sentencesOverview, .wind, .hydro, .compass, .manual:
            return .ephemeral
        }
    }

    /// Full detail size for the retained dashboard host across all pages so `MKMapView`
    /// keeps its Metal drawable and tiles warm without flashing on revisit.
    /// Host visibility, alpha, hit-testing, and accessibility hide it off the dashboard.
    func retainedDashboardSize(fitting detail: CGSize) -> CGSize {
        _ = self
        return detail
    }

    var rawValue: String {
        switch self {
        case .gps: return "gps"
        case .connection: return "connection"
        case .simulation: return "simulation"
        case .sentencesOverview: return "sentencesOverview"
        case .wind: return "wind"
        case .hydro: return "hydro"
        case .compass: return "compass"
        case .boat: return "boat"
        case .diagnostics: return "diagnostics"
        case .dashboard: return "dashboard"
        case .manual: return "manual"
        }
    }
}
