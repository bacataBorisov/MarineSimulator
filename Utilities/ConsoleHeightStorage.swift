import SwiftUI

/// Single console height preference (migrates legacy keys once).
enum ConsoleHeightStorage {
    static let key = "console_panel.height"
    private static let legacyMainKey = "main_view.console_height"
    private static let legacyDashboardKey = "dashboard.console_height"

    static func migrateIfNeeded(defaultHeight: Double = 220) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) != nil { return }

        let main = defaults.double(forKey: legacyMainKey)
        let dash = defaults.double(forKey: legacyDashboardKey)
        let chosen: Double
        if dash > 28 { chosen = dash }
        else if main > 28 { chosen = main }
        else { chosen = defaultHeight }
        defaults.set(chosen, forKey: key)
    }

    static var binding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(UserDefaults.standard.double(forKey: key)) },
            set: { UserDefaults.standard.set(Double($0), forKey: key) }
        )
    }

    static var storedDouble: Double {
        get { UserDefaults.standard.double(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Log height only (0 = header parked, like Xcode). Missing key still defaults to 220.
    static var logHeight: CGFloat {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: key) == nil { return 220 }
            return CGFloat(max(0, defaults.double(forKey: key)))
        }
        set { defaultsSet(max(0, Double(newValue))) }
    }

    private static func defaultsSet(_ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
