import SwiftUI

/// Engineering view of one isolated experiment. Opening it does not prepare a run.
struct ExperimentDiagnosticsView: View {
    @Bindable var session: ExperimentDiagnosticsSession

    var body: some View {
        let readout = session.readout
        PageContainer(maxWidth: 880) {
            VStack(alignment: .leading, spacing: 16) {
                statusBanner(readout)
                controls
                truthSection(readout)
                measurementSection(readout)
                navigationSection(readout)
                sensorSection
                errorSection
                nmeaSection(readout)
            }
        }
        .navigationTitle("Experiment Diagnostics")
        .onAppear { session.allowsWallClockLoop = true }
        .onDisappear { session.pauseIfRunning() }
    }

    private func statusBanner(_ readout: ExperimentDiagnosticsReadout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(statusTitle(readout.phase), systemImage: statusSymbol(readout.phase))
                .font(.headline)
                .foregroundStyle(statusColor(readout.phase))
            Text(statusDetail(readout))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Simulation time \(quantity(readout.elapsedSeconds, digits: 2)) / \(quantity(readout.durationSeconds, digits: 0)) s")
                .font(.callout.monospacedDigit())
            if session.configurationChangesArePending {
                Text("Scenario and error edits apply on Prepare or Reset. This run keeps the values it started with.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let message = session.validationMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        GroupBox("Experiment Controls") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("Prepare") { session.prepare() }
                    Button("Start") { session.start() }
                        .disabled(session.phase != .prepared)
                    Button("Pause") { session.pause() }
                        .disabled(session.phase != .running)
                    Button("Resume") { session.resume() }
                        .disabled(session.phase != .paused)
                    Button("Reset") { session.reset() }
                        .disabled(session.phase == .idle)
                }
                Text("Prepare and Reset build a fresh measurement sequence from the fields below. The operator simulator is left unchanged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DiagnosticValueField(
                    title: "Seed",
                    unit: "",
                    value: String(session.seed),
                    commit: { session.setSeed($0) }
                )
                DiagnosticValueField(
                    title: "Wind direction",
                    unit: "°",
                    value: quantity(session.windDirectionDegrees, digits: 1),
                    commit: { commit($0, session.setWindDirection) }
                )
                DiagnosticValueField(
                    title: "Wind speed",
                    unit: "kn",
                    value: quantity(session.windSpeedKnots, digits: 1),
                    commit: { commit($0, session.setWindSpeed) }
                )
                DiagnosticValueField(
                    title: "Duration",
                    unit: "s",
                    value: quantity(session.durationSeconds, digits: 0),
                    commit: { commit($0, session.setDuration) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func truthSection(_ readout: ExperimentDiagnosticsReadout) -> some View {
        GroupBox("Physical Truth") {
            VStack(alignment: .leading, spacing: 4) {
                labeled("True wind speed", speed(readout.trueWindSpeedKnots))
                labeled("True wind direction", angle(readout.trueWindDirectionDegrees))
                labeled("True heading", angle(readout.trueHeadingDegrees))
                labeled("Speed through water", speed(readout.speedThroughWaterKnots))
                labeled("Speed over ground", speed(readout.speedOverGroundKnots))
                labeled("Course over ground", angle(readout.courseOverGroundDegrees))
                labeled("Latitude", coordinate(readout.latitude))
                labeled("Longitude", coordinate(readout.longitude))
                labeled("Ideal apparent wind speed", speed(readout.idealApparentWindSpeedKnots))
                labeled("Ideal apparent wind angle", angle(readout.idealApparentWindAngleDegrees))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func measurementSection(_ readout: ExperimentDiagnosticsReadout) -> some View {
        GroupBox("Instrument Measurements") {
            VStack(alignment: .leading, spacing: 4) {
                comparison("AWS", measured: readout.apparentWindSpeedKnots, reference: readout.idealApparentWindSpeedKnots, unit: "kn", circular: false)
                comparison("AWA", measured: readout.apparentWindAngleDegrees, reference: readout.idealApparentWindAngleDegrees, unit: "°", circular: true)
                comparison("STW", measured: readout.measuredSpeedThroughWaterKnots, reference: readout.speedThroughWaterKnots, unit: "kn", circular: false)
                comparison("True heading", measured: readout.measuredTrueHeadingDegrees, reference: readout.trueHeadingDegrees, unit: "°", circular: true)
                labeled("Magnetic compass", angle(readout.magneticCompassHeadingDegrees))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func navigationSection(_ readout: ExperimentDiagnosticsReadout) -> some View {
        GroupBox("Calculated Navigation Values") {
            VStack(alignment: .leading, spacing: 4) {
                comparison("TWS", measured: readout.calculatedTrueWindSpeedKnots, reference: readout.trueWindSpeedKnots, unit: "kn", circular: false)
                comparison("TWA", measured: readout.calculatedTrueWindAngleDegrees, reference: idealTrueWindAngle(readout), unit: "°", circular: true)
                comparison("TWD", measured: readout.calculatedTrueWindDirectionDegrees, reference: readout.trueWindDirectionDegrees, unit: "°", circular: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sensorSection: some View {
        GroupBox("Sensor Availability") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Wind instrument", isOn: $session.windInstrument)
                Toggle("Speed log", isOn: $session.speedLog)
                Toggle("True heading instrument", isOn: $session.trueHeadingInstrument)
                Toggle("Magnetic compass", isOn: $session.magneticCompass)
                Text("These are the experiment’s anemometer, speed log, gyro, and compass switches. A change applies on the next step and does not move the boat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorSection: some View {
        GroupBox("Error Configuration") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bias and noise apply on Prepare or Reset. Noise amplitude cannot be negative. Nothing here is saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                errorRow("AWS", unit: "kn", channel: .apparentWindSpeed)
                errorRow("AWA", unit: "°", channel: .apparentWindAngle)
                errorRow("STW", unit: "kn", channel: .speedThroughWater)
                errorRow("True heading", unit: "°", channel: .trueHeading)
                errorRow("Magnetic compass", unit: "°", channel: .magneticCompass)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nmeaSection(_ readout: ExperimentDiagnosticsReadout) -> some View {
        GroupBox("NMEA Output") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(readout.sentences, id: \.name) { sentence in
                    LabeledContent(sentence.name) {
                        Text(sentence.text ?? "Unavailable")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(sentence.text == nil ? .secondary : .primary)
                    }
                }
                Text("Sentences come from the stored sample. Refreshing this page does not draw a new measurement.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorRow(_ title: String, unit: String, channel: ExperimentDiagnosticsSession.Channel) -> some View {
        let error = error(for: channel)
        return HStack(spacing: 16) {
            Text(title).frame(width: 140, alignment: .leading)
            DiagnosticValueField(title: "Bias", unit: unit, value: quantity(error.bias, digits: 2)) {
                commit($0) { session.setBias($0, for: channel) }
            }
            DiagnosticValueField(title: "Noise", unit: unit, value: quantity(error.noiseAmplitude, digits: 2)) {
                commit($0) { session.setNoiseAmplitude($0, for: channel) }
            }
        }
    }

    private func error(for channel: ExperimentDiagnosticsSession.Channel) -> SensorChannelError {
        switch channel {
        case .apparentWindSpeed: session.errors.apparentWindSpeed
        case .apparentWindAngle: session.errors.apparentWindAngle
        case .speedThroughWater: session.errors.speedThroughWater
        case .trueHeading: session.errors.trueHeading
        case .magneticCompass: session.errors.magneticCompass
        }
    }

    private func comparison(_ title: String, measured: Double?, reference: Double?, unit: String, circular: Bool) -> some View {
        let text: String
        if let measured {
            let measuredText = "\(quantity(measured, digits: circular ? 1 : 2)) \(unit)"
            if let reference {
                let delta = circular
                    ? ExperimentDiagnosticsReadout.signedAngleDelta(from: reference, to: measured)
                    : measured - reference
                text = "\(measuredText) · reference \(quantity(reference, digits: circular ? 1 : 2)) · Δ \(signed(delta, digits: circular ? 1 : 2)) \(unit)"
            } else {
                text = measuredText
            }
        } else {
            text = "Unavailable"
        }
        return labeled(title, text)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(value == "Unavailable" ? .secondary : .primary)
        }
    }

    private func idealTrueWindAngle(_ readout: ExperimentDiagnosticsReadout) -> Double? {
        guard let direction = readout.trueWindDirectionDegrees, let heading = readout.trueHeadingDegrees else { return nil }
        return ExperimentSensorModel.trueWindAngleDegrees(trueHeading: heading, trueWindDirection: direction)
    }

    private func speed(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return "\(quantity(value, digits: 2)) kn"
    }

    private func angle(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return "\(quantity(value, digits: 1))°"
    }

    private func coordinate(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return quantity(value, digits: 5)
    }

    private func quantity(_ value: Double, digits: Int) -> String {
        NMEANumericFormatting.format(value, fractionDigits: digits)
    }

    private func signed(_ value: Double, digits: Int) -> String {
        let text = quantity(value, digits: digits)
        return value > 0 ? "+\(text)" : text
    }

    private func commit(_ text: String, _ setter: (Double) -> Bool) -> Bool {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            session.rejectUnreadableNumber()
            return false
        }
        return setter(value)
    }

    private func statusTitle(_ phase: ExperimentDiagnosticsSession.Phase) -> String {
        switch phase {
        case .idle: "Experimental mode inactive"
        case .prepared: "Experimental mode prepared"
        case .running: "Experimental mode running"
        case .paused: "Experimental mode paused"
        case .complete: "Experimental mode complete"
        }
    }

    private func statusDetail(_ readout: ExperimentDiagnosticsReadout) -> String {
        switch readout.phase {
        case .idle:
            "The operator simulator is unchanged. Prepare an experiment to sample the instrument models."
        case .prepared:
            "The experiment is ready. Start advances the simulation clock."
        case .running:
            "This window is stepping the isolated experiment. Operator NMEA is not using these measurements."
        case .paused:
            "Advancement is stopped. Resume continues the same measurement sequence."
        case .complete:
            "The scenario duration has elapsed. Reset starts the same scenario from the first sample."
        }
    }

    private func statusSymbol(_ phase: ExperimentDiagnosticsSession.Phase) -> String {
        switch phase {
        case .idle: "circle"
        case .prepared: "circle.dotted"
        case .running: "circle.fill"
        case .paused: "pause.circle"
        case .complete: "checkmark.circle"
        }
    }

    private func statusColor(_ phase: ExperimentDiagnosticsSession.Phase) -> Color {
        switch phase {
        case .idle: .secondary
        case .prepared, .paused: .orange
        case .running: .green
        case .complete: .primary
        }
    }
}

private struct DiagnosticValueField: View {
    let title: String
    let unit: String
    let value: String
    let commit: (String) -> Bool
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: $text)
                    .frame(width: 110)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { invalid = !commit(text) }
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                }
            }
        }
        .foregroundStyle(invalid ? .red : .primary)
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in
            text = newValue
            invalid = false
        }
    }
}
