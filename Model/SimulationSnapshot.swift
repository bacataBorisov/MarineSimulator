import Foundation

struct GPSSatelliteSnapshot {
    let prn: Int
    let elevation: Int
    let azimuth: Int
    let snr: Int
    let isUsedInFix: Bool
}

struct GPSSignalSnapshot {
    let fixQuality: Int
    let fixMode: Int
    let selectionMode: String
    let satellitesUsed: Int
    let hdop: Double
    let vdop: Double
    let pdop: Double
    let altitudeMeters: Double
    let geoidalSeparationMeters: Double
    let satellites: [GPSSatelliteSnapshot]
}

struct SimulationSnapshot {
    let timestamp: Date
    let windDirectionTrue: Double?
    let windSpeedTrue: Double?
    let magneticHeading: Double?
    let gyroHeading: Double?
    let magneticVariation: Double
    let compassDeviation: Double
    let boatSpeed: Double?
    let depth: Double?
    let seaTemperature: Double?
    let airTemperature: Double?
    let relativeHumidity: Double?
    let airPressure: Double?
    let gpsData: GPSData
    let gpsSignal: GPSSignalSnapshot
    let turnRate: Double
    let logDistanceNm: Double
    let tripDistanceNm: Double
}
