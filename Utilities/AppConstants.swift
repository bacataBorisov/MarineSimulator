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

public struct UIConstants {
    
    static let spacing: CGFloat = 6
    static let halfScreen = (NSScreen.main?.frame.width ?? 1728) / 2
    static let minAppWindowHeight = 520 + (3 * spacing)
    static let tabBarHeight: CGFloat = 32
    static let bottomBarHeight: CGFloat = 24
    
}

public enum UIStrings {

    enum Warnings {
        
        static let enableAnemometer = "Enable Anemometer in Configuration to activate sentences."
        static let enableEchoSounder = "Enable Echo Sounder in Configuration to activate sentences."
        static let invalidDepthOffset = "Please enter a valid non-zero depth offset (e.g., 0.30 or -0.70) to activate DPT."
        static let enableWaterTempSensor = "Enable Water Temp Sensor in Configuration to activate sentences."
        static let enableMagneticCompass = "Enable Compass in Configuration to activate sentences."
        static let enableGyroCompass = "Enable Gyro Compass in Configuration to activate sentences."
        static let enableSpeedLog = "Enable Speed Log in Configuration to activate sentences."
        static let enableGPS = "Enable GPS in Configuration to activate sentences."

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


