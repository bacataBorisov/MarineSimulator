//
//  SensorToggles.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 24.06.25.
//

import Foundation

struct SensorToggleStates: Codable {
    
    // Wind
    var hasAnemometer: Bool = false

    
    // Compass / Gyro
    var hasCompass: Bool = false
    var hasGyro: Bool = false


    // GPS
    var hasGPS: Bool = false
    var hasAIS: Bool = false

    //MARK: - Hydro Data
    // Depth
    var hasEchoSounder = false
    
    // Speed / Log
    var hasSpeedLog = false
    
    // Sea Water Temperature
    var hasWaterTempSensor = false
    
    //MARK: - Environmental Sensors
    var hasAirTempSensor: Bool = false
    var hasHumidtySensor: Bool = false
    var hasBarometer: Bool = false
    
    //MARK: - Satellite & Communication
    var shouldSendGNSS: Bool = false
    var shouldSendDSC: Bool = false
    
}
