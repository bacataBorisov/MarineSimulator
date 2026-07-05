import Foundation

/// Read-only snapshot of user-facing configuration captured at the start of each simulation cycle.
///
/// The off-main transmit loop grabs one of these from the main thread at the top of every
/// cycle so it can read toggles, intervals, and modes without touching `@Observable` state.
struct SimulationConfig {
    let sensorToggles: SensorToggleStates
    let sentenceToggles: SentenceToggleStates
    let interval: Double
    let sentenceIntervals: [NMEASentenceType: TimeInterval]
    let weatherSourceMode: WeatherSourceMode
    let latestLiveWeather: LiveWeatherSnapshot?
    let boatSpeedMode: BoatSpeedMode
    let boatProfile: BoatProfile
    let waypointNavigation: WaypointNavigation
    let tackAnimationInProgress: Bool
    let talkerID: String
    let perSentenceTalkerID: [NMEASentenceType: String]
    let depthOffsetMeters: Double
    let faultInjection: FaultInjectionSettings
    let mwvReferenceMode: MWVReferenceMode
    let enabledOutputEndpoints: [OutputEndpoint]
}
