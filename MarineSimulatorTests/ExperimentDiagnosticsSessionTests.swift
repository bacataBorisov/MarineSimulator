import Foundation
import Testing
@testable import MarineSimulator

@MainActor
@Suite(.serialized)
struct ExperimentDiagnosticsSessionTests {

    @Test
    func preparingCreatesAnExperimentalRuntime() {
        let session = ExperimentDiagnosticsSession()
        #expect(session.phase == .idle)
        #expect(session.runtime?.state.experimentInstruments == nil)
        session.prepare()
        #expect(session.phase == .prepared)
        #expect(session.runtime?.state.experimentInstruments != nil)
        #expect(session.elapsedSeconds == 0)
        #expect(session.readout.apparentWindSpeedKnots == nil)
    }

    @Test
    func startingAdvancesAndPauseResumeKeepTheSameSequence() {
        let session = ExperimentDiagnosticsSession()
        let twin = ExperimentDiagnosticsSession()
        session.prepare()
        twin.prepare()
        session.advance()
        #expect(session.elapsedSeconds == 0)
        session.start()
        #expect(session.elapsedSeconds == ExperimentDiagnosticsSession.physicsInterval)
        let paused = session.elapsedSeconds
        session.pause()
        session.advance()
        #expect(session.elapsedSeconds == paused)
        session.resume()
        twin.start()
        twin.advance()
        #expect(session.elapsedSeconds == twin.elapsedSeconds)
        expectClose(session.readout.trueHeadingDegrees, twin.readout.trueHeadingDegrees)
        expectClose(session.readout.latitude, twin.readout.latitude)
        #expect(session.readout.sentences == twin.readout.sentences)
    }

    @Test
    func resetRestartsTheMeasurementSequence() {
        let session = ExperimentDiagnosticsSession()
        session.prepare()
        session.start()
        session.advance()
        let first = session.readout
        session.reset()
        #expect(session.phase == .prepared)
        #expect(session.elapsedSeconds == 0)
        #expect(session.readout.apparentWindSpeedKnots == nil)
        session.start()
        session.advance()
        #expect(session.readout.sentences == first.sentences)
        expectClose(session.readout.latitude, first.latitude)
        expectClose(session.readout.measuredTrueHeadingDegrees, first.measuredTrueHeadingDegrees)
    }

    @Test
    func truthAndMeasurementsStaySeparate() {
        let session = ExperimentDiagnosticsSession()
        #expect(session.setBias(1.5, for: .apparentWindSpeed))
        session.prepare()
        session.start()
        let readout = session.readout
        expectClose(readout.trueWindSpeedKnots, 12)
        expectClose(readout.apparentWindSpeedKnots, (readout.idealApparentWindSpeedKnots ?? 0) + 1.5)
        #expect(readout.apparentWindSpeedKnots != readout.trueWindSpeedKnots)
    }

    @Test
    func disabledWindInstrumentOmitsTheMeasurementAndLeavesTheWind() {
        let session = ExperimentDiagnosticsSession()
        session.windInstrument = false
        session.prepare()
        session.start()
        #expect(session.readout.apparentWindSpeedKnots == nil)
        #expect(session.readout.apparentWindAngleDegrees == nil)
        #expect(session.readout.calculatedTrueWindSpeedKnots == nil)
        expectClose(session.readout.trueWindSpeedKnots, 12)
        #expect(session.readout.windInstrument == false)
        #expect(session.readout.speedLog == true)
        #expect(session.readout.trueHeadingInstrument == true)
        #expect(session.readout.magneticCompass == true)
    }

    @Test
    func errorConfigurationReachesTheMeasurementModel() {
        let calm = ExperimentDiagnosticsSession()
        let biased = ExperimentDiagnosticsSession()
        #expect(biased.setBias(0.4, for: .speedThroughWater))
        calm.prepare()
        biased.prepare()
        calm.start()
        biased.start()
        expectClose(
            biased.readout.measuredSpeedThroughWaterKnots,
            (calm.readout.measuredSpeedThroughWaterKnots ?? 0) + 0.4
        )
        #expect(biased.runtime?.state.experimentInstruments?.errors.speedThroughWater.bias == 0.4)
    }

    @Test
    func invalidConfigurationIsRejected() {
        let session = ExperimentDiagnosticsSession()
        #expect(!session.setNoiseAmplitude(-1, for: .apparentWindAngle))
        #expect(session.errors.apparentWindAngle.noiseAmplitude == 0)
        #expect(!session.setBias(.infinity, for: .trueHeading))
        #expect(session.errors.trueHeading.bias == 0)
        #expect(!session.setSeed("seed"))
        #expect(session.seed == 1)
        #expect(!session.setWindSpeed(-2))
        #expect(session.windSpeedKnots == 12)
        #expect(!session.setDuration(0))
        #expect(session.durationSeconds == 1_800)
        #expect(session.validationMessage != nil)
    }

    @Test
    func identicalSeedsRepeatTheDiagnosticsReadout() {
        let first = ExperimentDiagnosticsSession()
        let second = ExperimentDiagnosticsSession()
        #expect(first.setSeed("42"))
        #expect(second.setSeed("42"))
        #expect(first.setNoiseAmplitude(3, for: .trueHeading))
        #expect(second.setNoiseAmplitude(3, for: .trueHeading))
        first.prepare()
        second.prepare()
        first.start()
        second.start()
        first.advance()
        second.advance()
        #expect(first.readout.sentences == second.readout.sentences)
        expectClose(first.readout.measuredTrueHeadingDegrees, second.readout.measuredTrueHeadingDegrees)
        expectClose(first.readout.latitude, second.readout.latitude)
    }

    @Test
    func refreshingSentencesDoesNotDrawAnotherSample() {
        let shown = ExperimentDiagnosticsSession()
        let quiet = ExperimentDiagnosticsSession()
        shown.prepare()
        quiet.prepare()
        shown.start()
        quiet.start()
        _ = shown.readout.sentences
        _ = shown.readout.sentences
        shown.advance()
        quiet.advance()
        #expect(shown.readout.sentences == quiet.readout.sentences)
        expectClose(shown.readout.apparentWindAngleDegrees, quiet.readout.apparentWindAngleDegrees)
    }

    @Test
    func experimentalNMEAUsesTheStoredPublication() {
        let session = ExperimentDiagnosticsSession()
        session.prepare()
        session.start()
        let readout = session.readout
        let fields = sentenceFields(named: "MWV true", in: readout)
        #expect(fields[2] == "T")
        #expect(fields[3] == NMEANumericFormatting.format(readout.calculatedTrueWindSpeedKnots ?? -1, fractionDigits: 1))
        let heading = sentenceFields(named: "HDT", in: readout)
        #expect(heading[1] == NMEANumericFormatting.format(readout.measuredTrueHeadingDegrees ?? -1, fractionDigits: 1))
    }

    @Test
    func aNormalOperatorSessionStaysUntouched() {
        let suite = "OperatorIsolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let simulator = NMEASimulator(userDefaults: defaults)
        simulator.heading.value = 123
        let session = ExperimentDiagnosticsSession()
        session.prepare()
        session.start()
        #expect(simulator.heading.value == 123)
        #expect(SimulationState(from: simulator).experimentInstruments == nil)
        #expect(session.runtime?.state.experimentInstruments != nil)
    }

    @Test
    func measurementErrorsDoNotChangeThePhysicalTrack() {
        let calm = ExperimentDiagnosticsSession()
        let biased = ExperimentDiagnosticsSession()
        #expect(biased.setBias(3, for: .apparentWindSpeed))
        #expect(biased.setBias(25, for: .trueHeading))
        #expect(biased.setBias(1, for: .speedThroughWater))
        calm.prepare()
        biased.prepare()
        calm.start()
        biased.start()
        for _ in 0..<4 {
            calm.advance()
            biased.advance()
        }
        expectClose(calm.readout.latitude, biased.readout.latitude)
        expectClose(calm.readout.longitude, biased.readout.longitude)
        expectClose(calm.readout.trueHeadingDegrees, biased.readout.trueHeadingDegrees)
        expectClose(calm.readout.speedThroughWaterKnots, biased.readout.speedThroughWaterKnots)
        #expect(calm.readout.measuredTrueHeadingDegrees != biased.readout.measuredTrueHeadingDegrees)
        #expect(biased.readout.sentences.allSatisfy { !($0.text ?? "").localizedCaseInsensitiveContains("nimana") })
        #expect(biased.readout.sentences.allSatisfy { !($0.text ?? "").localizedCaseInsensitiveContains("hidden") })
    }

    @Test
    func diagnosticsSessionComputesReferencePolarAndCurrentVectorAccurately() {
        let session = ExperimentDiagnosticsSession()
        #expect(session.setWindDirection(135))
        #expect(session.setWindSpeed(12))
        #expect(session.setBoatHeading(90))
        #expect(session.setCurrentSet(180))
        #expect(session.setCurrentDrift(2))
        #expect(session.setHullFactor(0.85))
        session.prepare()
        session.start()

        let readout = session.readout
        let expectedRef = BoatProfile.beneteauFirst407.estimatedBoatSpeed(trueWindSpeedKnots: 12, trueWindAngleDegrees: 45) ?? 0
        let expectedSTW = expectedRef * 0.85
        let expectedSOG = sqrt(expectedSTW * expectedSTW + 4.0)
        let expectedCOG = normalizeAngle(toDegrees(atan2(expectedSTW, -2.0)))

        expectClose(readout.referencePolarSpeedKnots, expectedRef)
        expectClose(readout.speedThroughWaterKnots, expectedSTW)
        expectClose(readout.speedOverGroundKnots, expectedSOG)
        expectClose(readout.courseOverGroundDegrees, expectedCOG)
    }

    @Test
    func diagnosticsSessionValidatesSweepAndFactorBounds() {
        let session = ExperimentDiagnosticsSession()
        #expect(!session.setWindDirectionSwing(200))
        #expect(!session.setWindSpeedAmplitude(-1))
        #expect(!session.setWindPeriod(2))
        #expect(!session.setCourseSweep(45))
        #expect(!session.setHullFactor(-0.1))
        #expect(!session.setSailFactor(4))
        #expect(!session.setCurrentDrift(-0.5))
        #expect(session.validationMessage != nil)
    }

    @Test
    func persistedInputsRestoreAcrossSessionsWhenBackedByUserDefaults() {
        let suite = "DiagnosticsPersistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ExperimentDiagnosticsSession(userDefaults: defaults)
        #expect(first.setSeed("77"))
        #expect(first.setWindDirection(160))
        #expect(first.setWindDirectionSwing(25))
        #expect(first.setWindSpeed(14.5))
        #expect(first.setWindSpeedAmplitude(3))
        #expect(first.setWindPeriod(90))
        #expect(first.setBoatHeading(215))
        #expect(first.setCourseSweep(1.5))
        #expect(first.setCurrentSet(45))
        #expect(first.setCurrentDrift(1.75))
        #expect(first.setDuration(900))
        first.hiddenPerformance.speedResponse = .firstOrder
        #expect(first.setHullFactor(0.88))
        #expect(first.setBias(1.2, for: .apparentWindSpeed))
        #expect(first.setNoiseAmplitude(0.4, for: .speedThroughWater))
        first.magneticCompass = false

        let restored = ExperimentDiagnosticsSession(userDefaults: defaults)
        #expect(restored.seed == 77)
        #expect(restored.windDirectionDegrees == 160)
        #expect(restored.windDirectionSwingDegrees == 25)
        #expect(restored.windSpeedKnots == 14.5)
        #expect(restored.windSpeedAmplitudeKnots == 3)
        #expect(restored.windPeriodSeconds == 90)
        #expect(restored.boatHeadingDegrees == 215)
        #expect(restored.courseSweepDegreesPerSecond == 1.5)
        #expect(restored.currentSetDegrees == 45)
        #expect(restored.currentDriftKnots == 1.75)
        #expect(restored.durationSeconds == 900)
        #expect(restored.hiddenPerformance.speedResponse == .firstOrder)
        #expect(restored.hiddenPerformance.hullFactor == 0.88)
        #expect(restored.errors.apparentWindSpeed.bias == 1.2)
        #expect(restored.errors.speedThroughWater.noiseAmplitude == 0.4)
        #expect(restored.magneticCompass == false)
    }
}

private func sentenceFields(named name: String, in readout: ExperimentDiagnosticsReadout) -> [String] {
    let sentence = readout.sentences.first { $0.name == name }?.text ?? ""
    let body = sentence.split(separator: "*").first.map(String.init) ?? sentence
    return body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
}

private func expectClose(_ value: Double?, _ expected: Double?) {
    #expect(abs((value ?? .nan) - (expected ?? .nan)) <= 1e-6)
}
