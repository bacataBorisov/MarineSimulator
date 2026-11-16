import SwiftUI

/// Engineering view of one isolated experiment. Opening it does not prepare a run.
struct ExperimentDiagnosticsView: View {
    @Bindable var session: ExperimentDiagnosticsSession

    var body: some View {
        let readout = session.readout
        PageContainer(maxWidth: PageChrome.maxWidth) {
            VStack(alignment: .leading, spacing: PageChrome.stackSpacing) {
                statusBanner(readout)
                controls
                hiddenPerformanceSection
                truthSection(readout)
                measurementSection(readout)
                navigationSection(readout)
                sensorSection
                errorSection
                nmeaSection(readout)
            }
        }
        .onAppear { session.allowsWallClockLoop = true }
        .onDisappear { session.pauseIfRunning() }
    }

    private func statusBanner(_ readout: ExperimentDiagnosticsReadout) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
            Label(statusTitle(readout.phase), systemImage: statusSymbol(readout.phase))
                .font(DesignToken.Typography.status.weight(.semibold))
                .foregroundStyle(statusColor(readout.phase))
            Text(statusDetail(readout))
                .font(DesignToken.Typography.supporting)
                .foregroundStyle(DesignToken.Status.neutral)
                .fixedSize(horizontal: false, vertical: true)
            Text("Simulation time \(quantity(readout.elapsedSeconds, digits: 2)) / \(quantity(readout.durationSeconds, digits: 0)) s")
                .font(DesignToken.Typography.supporting.monospacedDigit())
                .foregroundStyle(.primary)
            if session.configurationChangesArePending {
                Text("Scenario and error edits apply on Prepare or Reset. This run keeps the values it started with.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = session.validationMessage {
                Text(message)
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignToken.Spacing.card)
        .background(
            DesignToken.Surface.subtle,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.card, style: .continuous)
        )
    }

    private var controls: some View {
        SettingsCard(title: "Experiment Controls") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignToken.Spacing.row) {
                        controlButtons
                    }
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                        HStack(spacing: DesignToken.Spacing.row) {
                            prepareButton
                            startButton
                            pauseButton
                        }
                        HStack(spacing: DesignToken.Spacing.row) {
                            resumeButton
                            resetButton
                        }
                    }
                }
                Text("Prepare and Reset build a fresh measurement sequence from the fields below. The operator simulator is left unchanged.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
                DiagnosticValueField(
                    title: "Seed",
                    unit: "",
                    value: String(session.seed),
                    inputMode: .wholeNumber,
                    validationError: { raw in
                        UInt64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) == nil
                            ? "Seed must be a whole number from 0 upward."
                            : nil
                    },
                    commit: { session.setSeed($0) }
                )
                DiagnosticValueField(
                    title: "Wind direction",
                    unit: "°",
                    value: quantity(session.windDirectionDegrees, digits: 1),
                    inputMode: .signedDecimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite else {
                            return "Enter a valid wind direction in degrees."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setWindDirection) }
                )
                DiagnosticValueField(
                    title: "Wind speed",
                    unit: "kn",
                    value: quantity(session.windSpeedKnots, digits: 1),
                    inputMode: .decimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, v >= 0 else {
                            return "Wind speed must be zero or a positive number of knots."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setWindSpeed) }
                )
                DiagnosticValueField(
                    title: "Wind dir swing",
                    unit: "°",
                    value: quantity(session.windDirectionSwingDegrees, digits: 1),
                    inputMode: .decimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, (0...180).contains(v) else {
                            return "Wind swing must be between 0 and 180 degrees."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setWindDirectionSwing) }
                )
                DiagnosticValueField(
                    title: "Wind speed amp",
                    unit: "kn",
                    value: quantity(session.windSpeedAmplitudeKnots, digits: 1),
                    inputMode: .decimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, (0...40).contains(v) else {
                            return "Wind amplitude must be between 0 and 40 knots."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setWindSpeedAmplitude) }
                )
                DiagnosticValueField(
                    title: "Wind cycle period",
                    unit: "s",
                    value: quantity(session.windPeriodSeconds, digits: 0),
                    inputMode: .wholeNumber,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, (5...3_600).contains(v) else {
                            return "Wind period must be between 5 and 3,600 seconds."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setWindPeriod) }
                )
                DiagnosticValueField(
                    title: "Boat heading",
                    unit: "°",
                    value: quantity(session.boatHeadingDegrees, digits: 1),
                    inputMode: .signedDecimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite else {
                            return "Enter a valid boat heading in degrees."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setBoatHeading) }
                )
                DiagnosticValueField(
                    title: "Course sweep",
                    unit: "°/s",
                    value: quantity(session.courseSweepDegreesPerSecond, digits: 2),
                    inputMode: .signedDecimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, (-30...30).contains(v) else {
                            return "Course sweep must be between -30 and 30 °/s."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setCourseSweep) }
                )
                DiagnosticValueField(
                    title: "Current set",
                    unit: "°",
                    value: quantity(session.currentSetDegrees, digits: 1),
                    inputMode: .signedDecimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite else {
                            return "Enter a valid current set in degrees."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setCurrentSet) }
                )
                DiagnosticValueField(
                    title: "Current drift",
                    unit: "kn",
                    value: quantity(session.currentDriftKnots, digits: 2),
                    inputMode: .decimal,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, v >= 0 else {
                            return "Current drift must be zero or a positive number of knots."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setCurrentDrift) }
                )
                DiagnosticValueField(
                    title: "Duration",
                    unit: "s",
                    value: quantity(session.durationSeconds, digits: 0),
                    inputMode: .wholeNumber,
                    validationError: { raw in
                        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                              v.isFinite, (1...86_400).contains(v) else {
                            return "Duration must be between 1 and 86,400 seconds."
                        }
                        return nil
                    },
                    commit: { commit($0, session.setDuration) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        prepareButton
        startButton
        pauseButton
        resumeButton
        resetButton
    }

    @ViewBuilder
    private var prepareButton: some View {
        if session.phase == .idle {
            Button("Prepare") {
                commitFocusedFieldAndRun { session.prepare() }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Prepare") {
                commitFocusedFieldAndRun { session.prepare() }
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if session.phase == .prepared {
            Button("Start") {
                commitFocusedFieldAndRun { session.start() }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Start") {
                commitFocusedFieldAndRun { session.start() }
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .disabled(true)
        }
    }

    private var pauseButton: some View {
        Button("Pause") { session.pause() }
            .buttonStyle(.bordered)
            .tint(.primary)
            .disabled(session.phase != .running)
    }

    @ViewBuilder
    private var resumeButton: some View {
        if session.phase == .paused {
            Button("Resume") { session.resume() }
                .buttonStyle(.borderedProminent)
        } else {
            Button("Resume") { session.resume() }
                .buttonStyle(.bordered)
                .tint(.primary)
                .disabled(true)
        }
    }

    private var resetButton: some View {
        Button("Reset") {
            commitFocusedFieldAndRun { session.reset() }
        }
        .buttonStyle(.bordered)
        .tint(.primary)
        .disabled(session.phase == .idle)
    }

    private func commitFocusedFieldAndRun(_ action: @escaping () -> Void) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async {
            action()
        }
    }

    private var hiddenPerformanceSection: some View {
        SettingsCard(title: "Hidden Polar Factors") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                Text("Truth-only multipliers and speed lag applied behind the reference polar. Never emitted on NMEA.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Speed response") {
                    Picker("Speed response", selection: $session.hiddenPerformance.speedResponse) {
                        ForEach(SpeedResponse.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                DiagnosticValueField(
                    title: "Hull factor",
                    unit: "×",
                    value: quantity(session.hiddenPerformance.hullFactor, digits: 2),
                    inputMode: .decimal,
                    validationError: { factorValidation($0, label: "Hull factor") },
                    commit: { commit($0, session.setHullFactor) }
                )
                DiagnosticValueField(
                    title: "Sail factor",
                    unit: "×",
                    value: quantity(session.hiddenPerformance.sailFactor, digits: 2),
                    inputMode: .decimal,
                    validationError: { factorValidation($0, label: "Sail factor") },
                    commit: { commit($0, session.setSailFactor) }
                )
                DiagnosticValueField(
                    title: "Trim efficiency",
                    unit: "×",
                    value: quantity(session.hiddenPerformance.trimEfficiency, digits: 2),
                    inputMode: .decimal,
                    validationError: { factorValidation($0, label: "Trim efficiency") },
                    commit: { commit($0, session.setTrimEfficiency) }
                )
                DiagnosticValueField(
                    title: "Sea state factor",
                    unit: "×",
                    value: quantity(session.hiddenPerformance.seaStateFactor, digits: 2),
                    inputMode: .decimal,
                    validationError: { factorValidation($0, label: "Sea state factor") },
                    commit: { commit($0, session.setSeaStateFactor) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func factorValidation(_ raw: String, label: String) -> String? {
        guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              v.isFinite, (0...3).contains(v) else {
            return "\(label) must be between 0 and 3."
        }
        return nil
    }

    private func truthSection(_ readout: ExperimentDiagnosticsReadout) -> some View {
        SettingsCard(title: "Physical Truth") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
                labeled("True wind speed", speed(readout.trueWindSpeedKnots))
                labeled("True wind direction", angle(readout.trueWindDirectionDegrees))
                labeled("Current set", angle(readout.currentSetDegrees))
                labeled("Current drift", speed(readout.currentDriftKnots))
                labeled("True heading", angle(readout.trueHeadingDegrees))
                labeled("Speed through water", waterSpeedSummary(readout))
                labeled("Reference polar STW", speed(readout.referencePolarSpeedKnots))
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
        SettingsCard(title: "Instrument Measurements") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
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
        SettingsCard(title: "Calculated Navigation Values") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
                comparison("TWS", measured: readout.calculatedTrueWindSpeedKnots, reference: readout.trueWindSpeedKnots, unit: "kn", circular: false)
                comparison("TWA", measured: readout.calculatedTrueWindAngleDegrees, reference: idealTrueWindAngle(readout), unit: "°", circular: true)
                comparison("TWD", measured: readout.calculatedTrueWindDirectionDegrees, reference: readout.trueWindDirectionDegrees, unit: "°", circular: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sensorSection: some View {
        SettingsCard(title: "Sensor Availability") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                Toggle("Wind instrument", isOn: $session.windInstrument)
                Toggle("Speed log", isOn: $session.speedLog)
                Toggle("True heading instrument", isOn: $session.trueHeadingInstrument)
                Toggle("Magnetic compass", isOn: $session.magneticCompass)
                Text("These are the experiment’s anemometer, speed log, gyro, and compass switches. A change applies on the next step and does not move the boat.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorSection: some View {
        SettingsCard(title: "Error Configuration") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.row) {
                Text("Bias and noise apply on Prepare or Reset. Noise amplitude cannot be negative. Nothing here is saved.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
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
        SettingsCard(title: "NMEA Output") {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.stacked) {
                ForEach(readout.sentences, id: \.name) { sentence in
                    HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.field) {
                        let cleanText = sentence.text?.trimmingCharacters(in: .newlines)
                        Text(sentence.name)
                            .font(DesignToken.Typography.field)
                            .foregroundStyle(DesignToken.Status.neutral)
                            .frame(width: 112, alignment: .leading)
                        Text(cleanText ?? "Unavailable")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                            .foregroundStyle(cleanText == nil ? DesignToken.Status.neutral : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("\(sentence.name) NMEA sentence")
                            .accessibilityValue(cleanText ?? "Unavailable")
                    }
                }
                Text("Sentences come from the stored sample. Refreshing this page does not draw a new measurement.")
                    .font(DesignToken.Typography.supporting)
                    .foregroundStyle(DesignToken.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorRow(_ title: String, unit: String, channel: ExperimentDiagnosticsSession.Channel) -> some View {
        let error = error(for: channel)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignToken.Spacing.card) {
                Text(title)
                    .font(DesignToken.Typography.field)
                    .frame(width: ResponsiveLayout.formLabelWidth, alignment: .leading)
                errorFields(title: title, unit: unit, error: error, channel: channel)
            }
            VStack(alignment: .leading, spacing: DesignToken.Spacing.related) {
                Text(title)
                    .font(DesignToken.Typography.field.weight(.medium))
                errorFields(title: title, unit: unit, error: error, channel: channel)
            }
        }
    }

    @ViewBuilder
    private func errorFields(
        title: String,
        unit: String,
        error: SensorChannelError,
        channel: ExperimentDiagnosticsSession.Channel
    ) -> some View {
        DiagnosticValueField(
            title: "Bias",
            accessibilityTitle: "\(title) bias",
            unit: unit,
            value: quantity(error.bias, digits: 2),
            inputMode: .signedDecimal,
            validationError: { raw in
                guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite else {
                    return "Bias must be a finite number."
                }
                return nil
            }
        ) {
            commit($0) { session.setBias($0, for: channel) }
        }
        DiagnosticValueField(
            title: "Noise",
            accessibilityTitle: "\(title) noise",
            unit: unit,
            value: quantity(error.noiseAmplitude, digits: 2),
            inputMode: .decimal,
            validationError: { raw in
                guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite, v >= 0 else {
                    return "Noise amplitude must be zero or positive."
                }
                return nil
            }
        ) {
            commit($0) { session.setNoiseAmplitude($0, for: channel) }
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

    private func waterSpeedSummary(_ readout: ExperimentDiagnosticsReadout) -> String {
        guard let stw = readout.speedThroughWaterKnots else { return "Unavailable" }
        guard let reference = readout.referencePolarSpeedKnots, reference > 0 else {
            return "\(quantity(stw, digits: 2)) kn"
        }
        let percent = (stw / reference) * 100
        return "\(quantity(stw, digits: 2)) kn (\(quantity(percent, digits: 1))% of reference)"
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
        case .idle: DesignToken.Status.neutral
        case .prepared, .paused: DesignToken.Status.warning
        case .running: DesignToken.Status.success
        case .complete: .primary
        }
    }
}

private struct DiagnosticValueField: View {
    let title: String
    var accessibilityTitle: String? = nil
    let unit: String
    let value: String
    var inputMode: FormTextInputMode = .decimal
    var validationError: ((String) -> String?)? = nil
    let commit: (String) -> Bool

    @FocusState private var isFocused: Bool
    @State private var draftText: String
    @State private var isRevertingDraft = false
    @State private var committedMessage: String?
    @State private var inputHintMessage: String?
    @State private var showValidationPopover = false

    init(
        title: String,
        accessibilityTitle: String? = nil,
        unit: String,
        value: String,
        inputMode: FormTextInputMode = .decimal,
        validationError: ((String) -> String?)? = nil,
        commit: @escaping (String) -> Bool
    ) {
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.unit = unit
        self.value = value
        self.inputMode = inputMode
        self.validationError = validationError
        self.commit = commit
        self._draftText = State(initialValue: value)
    }

    private var accessibleLabel: String {
        let base = accessibilityTitle ?? title
        return unit.isEmpty ? base : "\(base) (\(unit))"
    }

    private var activePopoverMessage: String? {
        inputHintMessage ?? committedMessage
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: DesignToken.Spacing.related) {
                TextField(title, text: $draftText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .background(ResignFirstResponderOnOutsideClick(isActive: isFocused))
                    .accessibilityLabel(accessibleLabel)
                    .onSubmit {
                        commitAndValidate()
                        isFocused = false
                    }

                if !unit.isEmpty {
                    Text(unit)
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(DesignToken.Status.neutral)
                        .frame(width: 28, alignment: .leading)
                        .accessibilityHidden(true)
                }

                if let committedMessage {
                    Button {
                        showValidationPopover.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(DesignToken.Typography.supporting)
                            .foregroundStyle(DesignToken.Status.warning)
                    }
                    .buttonStyle(.plain)
                    .help(committedMessage)
                    .accessibilityLabel("\(accessibleLabel): \(committedMessage)")
                }
            }
            .popover(isPresented: $showValidationPopover, arrowEdge: .bottom) {
                if let message = activePopoverMessage {
                    Text(message)
                        .font(DesignToken.Typography.supporting)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DesignToken.Spacing.inset)
                        .frame(width: 220, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: draftText) { _, newValue in
            if isRevertingDraft {
                isRevertingDraft = false
                return
            }
            let sanitized = inputMode.sanitize(newValue)
            if sanitized != newValue, let hint = inputMode.hintMessage {
                isRevertingDraft = true
                draftText = sanitized
                NSSound.beep()
                inputHintMessage = hint
                showValidationPopover = true
            } else {
                inputHintMessage = nil
                if isFocused {
                    committedMessage = nil
                    showValidationPopover = false
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                committedMessage = nil
                showValidationPopover = false
            } else {
                inputHintMessage = nil
                commitAndValidate()
            }
        }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                if draftText != newValue {
                    draftText = newValue
                }
                committedMessage = validationError?(newValue)
            }
        }
    }

    private func commitAndValidate() {
        inputHintMessage = nil
        let message = validationError?(draftText)
        let accepted = commit(draftText)
        let resolvedMessage = message ?? (accepted ? nil : "Enter a valid number.")
        committedMessage = resolvedMessage
        showValidationPopover = resolvedMessage != nil
    }
}
