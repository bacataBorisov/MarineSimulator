import Foundation

/// Mutable simulation state owned by the fast transmit queue while `isTransmitting`.
///
/// During off-main-thread simulation, this struct holds the authoritative copies of all
/// sensor values, GPS data, emission scheduling, and weather noise offsets. When the
/// simulation cycle completes, its contents are applied back to the main-thread properties
/// of ``NMEASimulator`` via `applyRuntimeToMain`.
struct SimulationState {
    var lastSimulationTickDate: Date?
    var lastSensorEvolutionDate: Date?
    var lastEmissionDates: [NMEASentenceType: Date] = [:]
    var pendingTransmissions: [PendingTransmission] = []
    var previousTurnReferenceHeading: Double?
    var sendRelativeWind = true
    var totalLogDistanceNm: Double = 0
    var totalTripDistanceNm: Double = 0
    var liveWeatherWindSpeedOffsetKt: Double = 0
    var liveWeatherWindDirectionOffsetDeg: Double = 0
    var liveWeatherNoiseBaselineFetchDate: Date?
    var gpsData: GPSData
    var twd: SimulatedValue
    var tws: SimulatedValue
    var speed: SimulatedValue
    var depth: SimulatedValue
    var seaTemp: SimulatedValue
    var airTemp: SimulatedValue
    var humidity: SimulatedValue
    var barometer: SimulatedValue
    var heading: SimulatedValue
    var gyroHeading: SimulatedValue
    var latestSnapshot: SimulationSnapshot?

    init(from simulator: NMEASimulator) {
        gpsData = simulator.gpsData
        twd = simulator.twd
        tws = simulator.tws
        speed = simulator.speed
        depth = simulator.depth
        seaTemp = simulator.seaTemp
        airTemp = simulator.airTemp
        humidity = simulator.humidity
        barometer = simulator.barometer
        heading = simulator.heading
        gyroHeading = simulator.gyroHeading
        latestSnapshot = simulator.latestSnapshot
        liveWeatherWindSpeedOffsetKt = simulator.liveWeatherWindSpeedOffsetKt
        liveWeatherWindDirectionOffsetDeg = simulator.liveWeatherWindDirectionOffsetDeg
        liveWeatherNoiseBaselineFetchDate = simulator.liveWeatherNoiseBaselineFetchDate
    }
}

/// A sentence that was built but not yet transmitted, waiting for its stagger delay.
struct PendingTransmission {
    let sentence: String
    let dueDate: Date
}
