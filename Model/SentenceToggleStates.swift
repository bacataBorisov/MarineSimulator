//
//  SentenceToggleStates.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 24.06.25.
//


// SentenceToggleStates.swift

import Foundation

struct SentenceToggleStates: Codable {
    
    // Wind

    var shouldSendMWV: Bool = true
    var shouldSendMWD: Bool = true
    var shouldSendVPW: Bool = true
    
    // Compass / Gyro

    var shouldSendHDG: Bool = true
    var shouldSendHDT: Bool = true
    var shouldSendROT: Bool = true

    // GPS
    
    var shouldSendRMC: Bool = true
    var shouldSendGGA: Bool = true
    var shouldSendVTG: Bool = true
    var shouldSendGLL: Bool = true
    var shouldSendGSA: Bool = true
    var shouldSendGSV: Bool = true
    var shouldSendZDA: Bool = true
    
    // Depth
    var shouldSendDBT: Bool = true
    var shouldSendDPT: Bool = true
    
    // Speed / Log
    var shouldSendVHW: Bool = true
    var shouldSendVLW: Bool = true
    var shouldSendVBW: Bool = true
    
    // Temperature
    var shouldSendMTW: Bool = true
}
