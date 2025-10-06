//
//  NMEASimulator+FormattedValues.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 17.06.25.
//

extension NMEASimulator {
    
    // MARK: - Formatted Outputs for UI Display

    
    // Wind
    var formattedAWA: String { FormatKit.formattedValue(calculatedAWA, decimals: 0) }
    var formattedAWS: String { FormatKit.formattedValue(calculatedAWS, decimals: 1) }
    var formattedAWD: String { FormatKit.formattedValue(calculatedAWD, decimals: 0) }
    var formattedTWA: String { FormatKit.formattedValue(calculatedTWA, decimals: 0) }
    var formattedTWS: String { FormatKit.formattedValue(tws.value, decimals: 1) }
    var formattedTWD: String { FormatKit.formattedValue(twd.value, decimals: 0) }
    
    // Hydro
    var formattedDepth: String { FormatKit.formattedValue(depth.value, decimals: 1) }
    var formattedSpeed: String { FormatKit.formattedValue(speed.value, decimals: 2) }
    var formattedTemperature: String { FormatKit.formattedValue(seaTemp.value, decimals: 1) }
    
}


