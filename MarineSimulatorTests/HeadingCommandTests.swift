import Foundation
import Testing
@testable import MarineSimulator

/// The gyro setpoint commands true heading. Magnetic center is true minus east variation
/// and must keep the whole circle, including 359.5°.
@Suite(.serialized)
struct HeadingCommandTests {

    @Test @MainActor
    func eastVariationKeepsWrappedMagneticHeading() {
        let simulator = makeHeadingCommandSimulator(variation: 0.5)
        let variation = currentVariation(simulator)
        #expect(variation > 0)
        #expect(abs(variation - 0.5) < 0.001)

        commandTrueHeading(0, on: simulator, previousGyro: 12)

        let magnetic = simulator.heading.centerValue
        #expect(magnetic > 359)
        #expect(magnetic < 360)
        #expect(simulator.gyroHeading.value == 12)
        #expect(abs(normalizeAngleTo180(normalizeAngle(magnetic + currentVariation(simulator)))) < 1e-4)

        simulator.runSimulationCycle(at: Date())
        let live = simulator.gyroHeading.value ?? .nan
        #expect(abs(normalizeAngleTo180(live)) < 1e-3)
    }

    @Test @MainActor
    func westVariationKeepsNear360TrueHeading() {
        let simulator = makeHeadingCommandSimulator(variation: -0.5)
        let variation = currentVariation(simulator)
        #expect(variation < 0)
        #expect(abs(variation + 0.5) < 0.001)

        commandTrueHeading(359, on: simulator, previousGyro: 12)

        let magnetic = simulator.heading.centerValue
        #expect(magnetic > 359)
        #expect(magnetic < 360)
        #expect(simulator.gyroHeading.value == 12)
        #expect(abs(normalizeAngleTo180(normalizeAngle(magnetic + currentVariation(simulator)) - 359)) < 1e-4)

        simulator.runSimulationCycle(at: Date())
        let live = simulator.gyroHeading.value ?? .nan
        #expect(abs(normalizeAngleTo180(live - 359)) < 1e-3)
    }
}

@MainActor
private func makeHeadingCommandSimulator(variation target: Double) -> NMEASimulator {
    let suite = "HeadingCommand.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let simulator = NMEASimulator(userDefaults: defaults)
    simulator.outputEndpoints[0].isEnabled = false
    simulator.sensorToggles.hasGyro = true
    simulator.sensorToggles.hasCompass = true
    let seasonal = sin(Date().timeIntervalSinceReferenceDate / 86_400 / 45) * 1.8
    simulator.gpsData = GPSData(
        latitude: 0,
        longitude: (target - seasonal) / 0.16,
        speedOverGround: 6,
        courseOverGround: 0
    )
    return simulator
}

@MainActor
private func commandTrueHeading(_ trueHeading: Double, on simulator: NMEASimulator, previousGyro: Double) {
    var gyro = simulator.gyroHeading
    gyro.centerValue = trueHeading
    gyro.offset = 0
    gyro.value = previousGyro
    simulator.setSimulatedValue(\.gyroHeading, to: gyro)
}

@MainActor
private func currentVariation(_ simulator: NMEASimulator) -> Double {
    SimulationEngine.simulatedMagneticVariation(for: simulator.gpsData, at: Date())
}
