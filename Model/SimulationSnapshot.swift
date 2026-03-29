import Foundation

struct SimulationSnapshot {
    let timestamp: Date
    let windDirectionTrue: Double?
    let windSpeedTrue: Double?
    let magneticHeading: Double?
    let gyroHeading: Double?
    let boatSpeed: Double?
    let depth: Double?
    let seaTemperature: Double?
    let gpsData: GPSData
    let turnRate: Double
    let logDistanceNm: Double
    let tripDistanceNm: Double
}
