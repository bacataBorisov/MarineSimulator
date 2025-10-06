//
//  GaugeMarkerCompass.swift
//  ExtasyCompleteNavigation
//
//  Created by Vasil Borisov on 25.11.24.
//
import Foundation

struct GaugeMarkerCompass: Identifiable, Hashable {
    let id = UUID()
    
    let degrees: Double
    let label: String
    
    init(degrees: Double, label: String) {
        self.degrees = degrees
        self.label = label
    }
    
    // adjust according to your needs
    static func labelSet() -> [GaugeMarkerCompass] {
        return [
            GaugeMarkerCompass(degrees: 0, label: "N"),
            GaugeMarkerCompass(degrees: 30, label: "30"),
            GaugeMarkerCompass(degrees: 60, label: "60"),
            GaugeMarkerCompass(degrees: 90, label: "E"),
            GaugeMarkerCompass(degrees: 120, label: "120"),
            GaugeMarkerCompass(degrees: 150, label: "150"),
            GaugeMarkerCompass(degrees: 180, label: "S"),
            GaugeMarkerCompass(degrees: 210, label: "210"),
            GaugeMarkerCompass(degrees: 240, label: "240"),
            GaugeMarkerCompass(degrees: 270, label: "W"),
            GaugeMarkerCompass(degrees: 300, label: "300"),
            GaugeMarkerCompass(degrees: 330, label: "330")
        ]
    }
}
