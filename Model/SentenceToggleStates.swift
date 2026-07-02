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

    // Navigation
    var shouldSendRMB: Bool = true
    var shouldSendXTE: Bool = true

    init(
        shouldSendMWV: Bool = true,
        shouldSendMWD: Bool = true,
        shouldSendVPW: Bool = true,
        shouldSendHDG: Bool = true,
        shouldSendHDT: Bool = true,
        shouldSendROT: Bool = true,
        shouldSendRMC: Bool = true,
        shouldSendGGA: Bool = true,
        shouldSendVTG: Bool = true,
        shouldSendGLL: Bool = true,
        shouldSendGSA: Bool = true,
        shouldSendGSV: Bool = true,
        shouldSendZDA: Bool = true,
        shouldSendDBT: Bool = true,
        shouldSendDPT: Bool = true,
        shouldSendVHW: Bool = true,
        shouldSendVLW: Bool = true,
        shouldSendVBW: Bool = true,
        shouldSendMTW: Bool = true,
        shouldSendRMB: Bool = true,
        shouldSendXTE: Bool = true
    ) {
        self.shouldSendMWV = shouldSendMWV
        self.shouldSendMWD = shouldSendMWD
        self.shouldSendVPW = shouldSendVPW
        self.shouldSendHDG = shouldSendHDG
        self.shouldSendHDT = shouldSendHDT
        self.shouldSendROT = shouldSendROT
        self.shouldSendRMC = shouldSendRMC
        self.shouldSendGGA = shouldSendGGA
        self.shouldSendVTG = shouldSendVTG
        self.shouldSendGLL = shouldSendGLL
        self.shouldSendGSA = shouldSendGSA
        self.shouldSendGSV = shouldSendGSV
        self.shouldSendZDA = shouldSendZDA
        self.shouldSendDBT = shouldSendDBT
        self.shouldSendDPT = shouldSendDPT
        self.shouldSendVHW = shouldSendVHW
        self.shouldSendVLW = shouldSendVLW
        self.shouldSendVBW = shouldSendVBW
        self.shouldSendMTW = shouldSendMTW
        self.shouldSendRMB = shouldSendRMB
        self.shouldSendXTE = shouldSendXTE
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Wind
        shouldSendMWV = try c.decodeIfPresent(Bool.self, forKey: .shouldSendMWV) ?? true
        shouldSendMWD = try c.decodeIfPresent(Bool.self, forKey: .shouldSendMWD) ?? true
        shouldSendVPW = try c.decodeIfPresent(Bool.self, forKey: .shouldSendVPW) ?? true

        // Compass / Gyro
        shouldSendHDG = try c.decodeIfPresent(Bool.self, forKey: .shouldSendHDG) ?? true
        shouldSendHDT = try c.decodeIfPresent(Bool.self, forKey: .shouldSendHDT) ?? true
        shouldSendROT = try c.decodeIfPresent(Bool.self, forKey: .shouldSendROT) ?? true

        // GPS
        shouldSendRMC = try c.decodeIfPresent(Bool.self, forKey: .shouldSendRMC) ?? true
        shouldSendGGA = try c.decodeIfPresent(Bool.self, forKey: .shouldSendGGA) ?? true
        shouldSendVTG = try c.decodeIfPresent(Bool.self, forKey: .shouldSendVTG) ?? true
        shouldSendGLL = try c.decodeIfPresent(Bool.self, forKey: .shouldSendGLL) ?? true
        shouldSendGSA = try c.decodeIfPresent(Bool.self, forKey: .shouldSendGSA) ?? true
        shouldSendGSV = try c.decodeIfPresent(Bool.self, forKey: .shouldSendGSV) ?? true
        shouldSendZDA = try c.decodeIfPresent(Bool.self, forKey: .shouldSendZDA) ?? true

        // Depth
        shouldSendDBT = try c.decodeIfPresent(Bool.self, forKey: .shouldSendDBT) ?? true
        shouldSendDPT = try c.decodeIfPresent(Bool.self, forKey: .shouldSendDPT) ?? true

        // Speed / Log
        shouldSendVHW = try c.decodeIfPresent(Bool.self, forKey: .shouldSendVHW) ?? true
        shouldSendVLW = try c.decodeIfPresent(Bool.self, forKey: .shouldSendVLW) ?? true
        shouldSendVBW = try c.decodeIfPresent(Bool.self, forKey: .shouldSendVBW) ?? true

        // Temperature
        shouldSendMTW = try c.decodeIfPresent(Bool.self, forKey: .shouldSendMTW) ?? true

        // Navigation
        shouldSendRMB = try c.decodeIfPresent(Bool.self, forKey: .shouldSendRMB) ?? true
        shouldSendXTE = try c.decodeIfPresent(Bool.self, forKey: .shouldSendXTE) ?? true
    }
}
