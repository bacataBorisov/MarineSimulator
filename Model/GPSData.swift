//
//  GPSData.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 13.06.25.
//


import Foundation
import CoreLocation

struct GPSData {
    var latitude: Double
    var longitude: Double
    var speedOverGround: Double // Speed Over Ground in knots
    var courseOverGround: Double // Course Over Ground in degrees

    mutating func updatePosition(deltaTime: TimeInterval, sog: Double, cog: Double) {
        // Convert speed to m/s (1 knot = 0.514444 m/s)
        let speedMS = sog * 0.514444
        let distance = speedMS * deltaTime // meters

        let earthRadius = 6_371_000.0 // meters
        let bearingRad = toRadians(cog)

        let lat1 = toRadians(latitude)
        let lon1 = toRadians(longitude)

        let lat2 = asin(sin(lat1) * cos(distance / earthRadius) +
                        cos(lat1) * sin(distance / earthRadius) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(distance / earthRadius) * cos(lat1),
                                cos(distance / earthRadius) - sin(lat1) * sin(lat2))

        latitude = toDegrees(lat2)
        longitude = toDegrees(lon2)
        
        self.speedOverGround = sog
        self.courseOverGround = cog
    }
}
