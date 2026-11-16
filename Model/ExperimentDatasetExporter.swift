import Foundation

/// One sampled row captured from an isolated experiment run.
///
/// Measurement fields come strictly from `SimulationSnapshot` (`experimentPublication`
/// and GPS output). Ground-truth fields are kept separately for optional evaluation
/// and are omitted from estimator exports unless `ExperimentOutputContract.permitsGroundTruthExport` is true.
struct ExperimentDatasetRow: Equatable, Sendable {
    var timestamp: Date
    var elapsedSeconds: TimeInterval

    // Permitted measurements (instrument / publication path)
    var measuredTrueWindDirectionDegrees: Double?
    var measuredTrueWindSpeedKnots: Double?
    var measuredTrueHeadingDegrees: Double?
    var measuredSpeedThroughWaterKnots: Double?
    var measuredSpeedOverGroundKnots: Double?
    var measuredCourseOverGroundDegrees: Double?
    var measuredLatitude: Double?
    var measuredLongitude: Double?

    // Ground truth (internal validation only)
    var truthTrueWindDirectionDegrees: Double?
    var truthTrueWindSpeedKnots: Double?
    var truthTrueHeadingDegrees: Double?
    var truthSpeedThroughWaterKnots: Double?
    var truthSpeedOverGroundKnots: Double?
    var truthCourseOverGroundDegrees: Double?
    var truthLatitude: Double?
    var truthLongitude: Double?
}

/// Buffers sampled experiment rows at `sampleIntervalSeconds` and serializes them
/// to CSV according to `ExperimentOutputContract`.
struct ExperimentDatasetRecorder: Equatable, Sendable {
    var sampleIntervalSeconds: TimeInterval
    private(set) var rows: [ExperimentDatasetRow] = []
    private var lastRecordedElapsedSeconds: TimeInterval?

    init(sampleIntervalSeconds: TimeInterval = 1) {
        self.sampleIntervalSeconds = sampleIntervalSeconds.isFinite && sampleIntervalSeconds > 0
            ? sampleIntervalSeconds
            : 1
    }

    mutating func reset(sampleIntervalSeconds: TimeInterval) {
        self.sampleIntervalSeconds = sampleIntervalSeconds.isFinite && sampleIntervalSeconds > 0
            ? sampleIntervalSeconds
            : 1
        rows.removeAll()
        lastRecordedElapsedSeconds = nil
    }

    mutating func recordIfDue(
        elapsedSeconds: TimeInterval,
        state: SimulationState,
        config: SimulationConfig
    ) {
        guard let snapshot = state.latestSnapshot else { return }
        if let lastRecordedElapsedSeconds,
           elapsedSeconds - lastRecordedElapsedSeconds + 1e-9 < sampleIntervalSeconds {
            return
        }

        let publication = snapshot.experimentPublication
        let hasGPS = config.sensorToggles.hasGPS
        let row = ExperimentDatasetRow(
            timestamp: snapshot.timestamp,
            elapsedSeconds: elapsedSeconds,
            measuredTrueWindDirectionDegrees: finite(publication?.trueWindDirectionDegrees),
            measuredTrueWindSpeedKnots: finite(publication?.trueWindSpeedKnots),
            measuredTrueHeadingDegrees: finite(publication?.resolvedTrueHeadingDegrees),
            measuredSpeedThroughWaterKnots: finite(publication?.speedThroughWaterKnots),
            measuredSpeedOverGroundKnots: hasGPS ? finite(snapshot.gpsData.speedOverGround) : nil,
            measuredCourseOverGroundDegrees: hasGPS ? finite(snapshot.gpsData.courseOverGround) : nil,
            measuredLatitude: hasGPS ? finite(snapshot.gpsData.latitude) : nil,
            measuredLongitude: hasGPS ? finite(snapshot.gpsData.longitude) : nil,
            truthTrueWindDirectionDegrees: finite(state.environmentTruth.trueWindDirection),
            truthTrueWindSpeedKnots: finite(state.environmentTruth.trueWindSpeedKnots),
            truthTrueHeadingDegrees: finite(state.vesselTruth.trueHeading),
            truthSpeedThroughWaterKnots: finite(state.vesselTruth.speedThroughWaterKnots),
            truthSpeedOverGroundKnots: finite(state.vesselTruth.speedOverGroundKnots),
            truthCourseOverGroundDegrees: finite(state.vesselTruth.courseOverGroundDegrees),
            truthLatitude: finite(state.vesselTruth.latitude),
            truthLongitude: finite(state.vesselTruth.longitude)
        )
        rows.append(row)
        lastRecordedElapsedSeconds = elapsedSeconds
    }

    /// Exports only the fields permitted by `contract`.
    /// By default (`ExperimentOutputContract.estimatorInput`), ground truth is excluded.
    func estimatorCSV(contract: ExperimentOutputContract = .estimatorInput) -> String {
        let cleanContract = contract.sanitized()
        let fields = cleanContract.measurementFields
        var headers = fields.map(\.rawValue)
        if cleanContract.permitsGroundTruthExport {
            headers.append(contentsOf: [
                "truthTrueWindDirection",
                "truthTrueWindSpeed",
                "truthTrueHeading",
                "truthSpeedThroughWater",
                "truthSpeedOverGround",
                "truthCourseOverGround",
                "truthLatitude",
                "truthLongitude"
            ])
        }

        var lines: [String] = [headers.joined(separator: ",")]
        lines.reserveCapacity(rows.count + 1)

        for row in rows {
            var values = fields.map { formattedField($0, in: row) }
            if cleanContract.permitsGroundTruthExport {
                values.append(contentsOf: [
                    formatOptional(row.truthTrueWindDirectionDegrees, digits: 3),
                    formatOptional(row.truthTrueWindSpeedKnots, digits: 3),
                    formatOptional(row.truthTrueHeadingDegrees, digits: 3),
                    formatOptional(row.truthSpeedThroughWaterKnots, digits: 4),
                    formatOptional(row.truthSpeedOverGroundKnots, digits: 4),
                    formatOptional(row.truthCourseOverGroundDegrees, digits: 3),
                    formatOptional(row.truthLatitude, digits: 6),
                    formatOptional(row.truthLongitude, digits: 6)
                ])
            }
            lines.append(values.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Exports physical truth separately for offline evaluation (never fed to the estimator).
    func evaluationTruthCSV() -> String {
        let headers = [
            "timestamp",
            "elapsedSeconds",
            "truthTrueWindDirection",
            "truthTrueWindSpeed",
            "truthTrueHeading",
            "truthSpeedThroughWater",
            "truthSpeedOverGround",
            "truthCourseOverGround",
            "truthLatitude",
            "truthLongitude"
        ]
        var lines: [String] = [headers.joined(separator: ",")]
        lines.reserveCapacity(rows.count + 1)

        for row in rows {
            let values = [
                formatTimestamp(row.timestamp),
                NMEANumericFormatting.format(row.elapsedSeconds, fractionDigits: 2),
                formatOptional(row.truthTrueWindDirectionDegrees, digits: 3),
                formatOptional(row.truthTrueWindSpeedKnots, digits: 3),
                formatOptional(row.truthTrueHeadingDegrees, digits: 3),
                formatOptional(row.truthSpeedThroughWaterKnots, digits: 4),
                formatOptional(row.truthSpeedOverGroundKnots, digits: 4),
                formatOptional(row.truthCourseOverGroundDegrees, digits: 3),
                formatOptional(row.truthLatitude, digits: 6),
                formatOptional(row.truthLongitude, digits: 6)
            ]
            lines.append(values.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func formattedField(_ field: ExperimentMeasurementField, in row: ExperimentDatasetRow) -> String {
        switch field {
        case .timestamp:
            return formatTimestamp(row.timestamp)
        case .trueWindDirection:
            return formatOptional(row.measuredTrueWindDirectionDegrees, digits: 3)
        case .trueWindSpeed:
            return formatOptional(row.measuredTrueWindSpeedKnots, digits: 3)
        case .trueHeading:
            return formatOptional(row.measuredTrueHeadingDegrees, digits: 3)
        case .speedThroughWater:
            return formatOptional(row.measuredSpeedThroughWaterKnots, digits: 4)
        case .speedOverGround:
            return formatOptional(row.measuredSpeedOverGroundKnots, digits: 4)
        case .courseOverGround:
            return formatOptional(row.measuredCourseOverGroundDegrees, digits: 3)
        case .latitude:
            return formatOptional(row.measuredLatitude, digits: 6)
        case .longitude:
            return formatOptional(row.measuredLongitude, digits: 6)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    private func formatOptional(_ value: Double?, digits: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return NMEANumericFormatting.format(value, fractionDigits: digits)
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
