//
//  Constants.swift
//  ExtasyCompleteNavigation
//
//  Created by Vasil Borisov on 18.11.24.
//
import Foundation
import AppKit
import SwiftUI

public enum RoundingPrecision {
    
    case whole
    case tenths
    case hundredths
}

//coeff. for converting to nautical miles
public let toNauticalMiles = 0.000539956803
public let toNauticalCables = 0.0053961007775
public let toBoatLengths = 0.083333333333
public let toMetersPerSecond = 0.514444444

enum DistanceUnit {
    case nauticalMiles
    case nauticalCables
    case meters
    case boatLength
}

/// Semantic tokens for the migrated setup and form UI.
/// Typography uses SwiftUI text styles. Surfaces and status colors use system colors.
/// `AppColors` keeps the console palette and the tinted status colors of pages that are not migrated.
enum DesignToken {
    enum Spacing {
        /// Label above a value when a form row stacks.
        static let stacked: CGFloat = 4
        /// A value and its unit, or other immediately related items.
        static let related: CGFloat = 6
        /// Rows inside a card, and neighboring commands.
        static let row: CGFloat = 8
        /// Status-wash padding, and the gap from a heading to its card.
        static let inset: CGFloat = 10
        /// Stacked headings, and the inset of a card nested in another card.
        static let header: CGFloat = 12
        /// Fields inside a settings card, and the compact form label-to-value gap.
        static let field: CGFloat = 14
        /// Inset of a setup settings card.
        static let card: CGFloat = 16
        /// Inset of a boat-profile section card.
        static let profileCard: CGFloat = 18
        /// Space between setup cards, and between two configuration columns.
        static let section: CGFloat = 20
        /// Inset of a sidebar page.
        static let page: CGFloat = 24
    }

    enum Radius {
        /// Setup settings card.
        static let card: CGFloat = 12
        /// Boat profile card and a card nested inside a settings card.
        static let compactCard: CGFloat = 10
        /// Status and warning washes.
        static let status: CGFloat = 8
    }

    enum Typography {
        static let supporting = Font.caption
        static let section = Font.title3.weight(.semibold)
        static let field = Font.body
        static let help = Font.caption2
        static let status = Font.callout
    }

    enum Surface {
        static let page = AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        static let card = AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        static let subtle = AnyShapeStyle(HierarchicalShapeStyle.quaternary.opacity(0.28))
        static let nested = AnyShapeStyle(HierarchicalShapeStyle.quaternary.opacity(0.22))
        static let selection = AnyShapeStyle(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
    }

    enum Separator {
        static let standard = Color(nsColor: .separatorColor)
    }

    /// Interactive accent. It is the system accent, not a status or selection color.
    /// A future branding change replaces this token only.
    static let accentPrimary = Color.accentColor

    enum Status {
        static let neutral = Color.secondary
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
    }

    enum Width {
        /// Readable column for pages other than Connection and Simulation.
        static let readable: CGFloat = 920
        /// Connection and Simulation column, including the page inset.
        static let adaptivePage: CGFloat = 1120
        static let configurationCardMinimum: CGFloat = 440
        static let configurationCardMaximum: CGFloat = 520
        static let sentenceCard: CGFloat = 520
    }

    enum Form {
        static let labelWidth: CGFloat = 152
        static let valueMinimum: CGFloat = 280
        static let valueIdeal: CGFloat = 320
        static let valueMaximum: CGFloat = 360
        static let editorMinimum: CGFloat = 88
    }

    enum Breakpoint {
        /// Available page content. Below this, the content class is Compact.
        static let regular: CGFloat = 720
        /// Two minimum configuration cards plus the section gutter: 440 + 20 + 440.
        static var wide: CGFloat {
            Width.configurationCardMinimum * 2 + Spacing.section
        }
    }

    /// The window minimum. It is not a content-size guarantee.
    enum Window {
        static let minimumWidth: CGFloat = 1080
        static let minimumHeight: CGFloat = 640
        static let defaultWidth: CGFloat = 1180
        static let defaultHeight: CGFloat = 760
    }
}

public struct UIConstants {

    /// Legacy 6-point gap for pages that are not on `DesignToken`. Not an alias of `DesignToken.Spacing`.
    static let spacing: CGFloat = 6
    static let halfScreen = (NSScreen.main?.frame.width ?? 1728) / 2
    static let minAppWindowHeight = 520 + (3 * spacing)
    static let tabBarHeight: CGFloat = 32
    static let bottomBarHeight: CGFloat = 24
    
}

/// Page-layout names for `DesignToken`. Connection and Simulation use
/// `ResponsiveLayout.adaptivePageMaxWidth`. Other pages keep `maxWidth`.
/// `previewColumnWidth` stays a sentence-page measurement, not a shared token.
enum PageChrome {
    static let padding = DesignToken.Spacing.page
    static let maxWidth = DesignToken.Width.readable
    static let stackSpacing = DesignToken.Spacing.section
    static let splitBreakpoint = DesignToken.Breakpoint.wide
    static let previewColumnWidth: CGFloat = 320
    static let sentenceCardMaxWidth = DesignToken.Width.sentenceCard
}

public enum UIStrings {

    enum Warnings {
        
        static let enableAnemometer = "Anemometer is off."
        static let enableEchoSounder = "Echo Sounder is off."
        static let invalidDepthOffset = "Please enter a valid non-zero depth offset (e.g., 0.30 or -0.70) to activate DPT."
        static let enableWaterTempSensor = "Water Temperature sensor is off."
        static let enableMagneticCompass = "Magnetic Compass is off."
        static let enableGyroCompass = "Gyro Compass is off."
        static let enableSpeedLog = "Speed Log is off."
        static let enableGPS = "GPS is off."
        static let enableAtmosphericSensor = "Air Temperature, Humidity, and Barometer are all off."

    }
    
    enum InfoMessage {
        static let compassInfoNote = "Compass is disabled – heading fields will be blank."
        static let speedLogInfoNote = "Speed Log is disabled – speed fields will be blank."
        static let sogInfoNote = "GPS is disabled – ground speed fields will be blank."
    }

    enum Labels {
        static let seaWaterTemperature = "Sea Water Temperature"
        static let hydroSpeedGroup = "Hydro & Speed Sentences"
    }
}

import SwiftUI

/// Tinted status colors for pages that still use this type, plus the console palette.
/// Migrated setup UI uses `DesignToken.Status`. Do not spread the console RGB values.
enum AppColors {
    static let warning = Color.orange.opacity(0.8)
    static let info = Color.blue.opacity(0.7)
    static let danger = Color.red.opacity(0.7)
    static let success = Color.green.opacity(0.7)

    static let consoleBackgroundStart = Color(red: 0.16, green: 0.09, blue: 0.21)
    static let consoleBackgroundMid = Color(red: 0.07, green: 0.16, blue: 0.20)
    static let consoleBackgroundEnd = Color(red: 0.05, green: 0.20, blue: 0.18)
    static let consoleLinePrimary = Color(red: 0.96, green: 0.84, blue: 0.95)
    static let consoleLineSecondary = Color(red: 0.76, green: 0.96, blue: 0.90)
    static let consoleChrome = Color(red: 0.10, green: 0.08, blue: 0.14)
}

#if DEBUG
/// Filter Xcode console for `[MarineSim][hang]`.
/// A 1 Hz `beat` line dumps counters; `STALL in=` is the scope that never returned.
enum HangProbe {
    enum Event: String {
        case display
        case apply
        case consoleSync
        case consoleReset
        case mapUpdate
        case mapZero
        case mapRegion
    }

    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    private static var section = "-"
    private static var lastMainBeat: CFAbsoluteTime = 0
    private static var startedAt: CFAbsoluteTime = 0
    private static var watchdog: DispatchSourceTimer?
    private static var started = false

    static func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        startedAt = CFAbsoluteTimeGetCurrent()
        lastMainBeat = startedAt
        lock.unlock()

        NSLog("[MarineSim][hang] start — filter this prefix")
        armMainPing()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1.5, repeating: 1.0)
        timer.setEventHandler {
            let now = CFAbsoluteTimeGetCurrent()
            lock.lock()
            let age = now - lastMainBeat
            let stuckIn = section
            lock.unlock()
            if age > 1.5 {
                NSLog("[MarineSim][hang] STALL main-silent=%.1fs t=%.0fs in=%@", age, now - startedAt, stuckIn)
            }
        }
        timer.resume()
        watchdog = timer
    }

    static func tick(_ event: Event) {
        lock.lock()
        counts[event.rawValue, default: 0] += 1
        lock.unlock()
    }

    static func note(_ event: Event, _ detail: String) {
        tick(event)
        NSLog("[MarineSim][hang] %@ %@", event.rawValue, detail)
    }

    static func enter(_ name: String) {
        lock.lock()
        section = name
        lock.unlock()
    }

    static func leave(_ name: String) {
        lock.lock()
        if section == name { section = "-" }
        lock.unlock()
    }

    private static func armMainPing() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let now = CFAbsoluteTimeGetCurrent()
            lock.lock()
            lastMainBeat = now
            let snapshot = counts
            counts.removeAll(keepingCapacity: true)
            let elapsed = now - startedAt
            lock.unlock()

            let parts = snapshot.keys.sorted().map { "\($0)=\(snapshot[$0] ?? 0)" }
            NSLog("[MarineSim][hang] beat t=%.0fs %@", elapsed, parts.joined(separator: " "))
            armMainPing()
        }
    }
}
#endif


