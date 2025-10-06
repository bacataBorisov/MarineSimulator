//
//  SensorToggles.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 24.06.25.
//

import Foundation

struct SensorToggleStates: Codable {
    
    // Wind
    var hasAnemometer: Bool = true

    
    // Compass / Gyro
    var hasCompass: Bool = true
    var hasGyro: Bool = true


    // GPS
    var hasGPS: Bool = true
    var hasAIS: Bool = false

    //MARK: - Hydro Data
    // Depth
    var hasEchoSounder = true
    
    // Speed / Log
    var hasSpeedLog = true
    
    // Sea Water Temperature
    var hasWaterTempSensor = true
    
    //MARK: - Environmental Sensors
    var hasAirTempSensor = false
    var hasHumidtySensor = false
    var hasBarometer = false
    
    //MARK: - Satellite & Communication
    var shouldSendGNSS = false
    var shouldSendDSC = false
    
}
