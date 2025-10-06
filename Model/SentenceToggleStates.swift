// SentenceToggleStates.swift

import Foundation

struct SentenceToggleStates: Codable {
    
    // Wind
    var shouldSendMWV: Bool = false
    var shouldSendMWD: Bool = false
    var shouldSendVPW: Bool = false
    
    // Compass / Gyro
    var shouldSendHDG: Bool = false
    var shouldSendHDT: Bool = false
    var shouldSendROT: Bool = false

    // GPS
    var shouldSendRMC: Bool = false
    var shouldSendGGA: Bool = false
    var shouldSendVTG: Bool = false
    
    // Depth
    var shouldSendDBT: Bool = false
    var shouldSendDPT: Bool = false
    
    // Speed / Log
    var shouldSendVHW: Bool = false
    var shouldSendVLW: Bool = false
    
    // ... add more as needed
}