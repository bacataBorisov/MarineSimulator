import Foundation

/// Setup inspection state. Highlighting a row does not change the active simulation vessel.
@Observable
final class VesselLibrarySession {
    var highlightedID: UUID?
    var editingSailID: UUID?
    var buffer = VesselEditBuffer()
    private(set) var lastResult: VesselLibraryResult = .idle
    /// Shown while typed text is not yet valid. It does not mean the last persisted profile changed.
    private(set) var validationMessage: String?
    /// Profile loads replace the buffer. Those assignments are not user edits.
    private var reloadDepth = 0
    /// Stops a successful autosave from re-entering through a published library update.
    private var isPersistingEdits = false
    private var isReloadingProfile: Bool { reloadDepth > 0 }

    enum VesselLibraryResult: Equatable {
        case idle
        case succeeded
        case failed(VesselProfileStoreError)
    }

    var lastChangeSucceeded: Bool {
        if case .succeeded = lastResult { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let error) = lastResult { return error.message }
        return nil
    }

    func dismissFailure() {
        if case .failed = lastResult {
            lastResult = .idle
        }
    }

    func report(_ error: VesselProfileStoreError) {
        lastResult = .failed(error)
    }

    func hasUnsavedChanges(in simulator: NMEASimulator) -> Bool {
        guard let profile = highlightedProfile(in: simulator) else { return false }
        let stored = VesselEditBuffer(profile: profile)
        if profile.origin == .builtIn {
            return buffer.sailSignature != stored.sailSignature
        }
        return buffer.signature != stored.signature
    }

    func show(_ id: UUID, on simulator: NMEASimulator) {
        reloadDepth += 1
        defer { reloadDepth -= 1 }
        highlightedID = id
        validationMessage = nil
        if let profile = highlightedProfile(in: simulator) {
            buffer = VesselEditBuffer(profile: profile)
            if editingSailID == nil || !buffer.sails.contains(where: { $0.id == editingSailID }) {
                editingSailID = buffer.sails.first?.id
            }
        }
    }

    func highlight(_ id: UUID) {
        highlightedID = id
    }

    func requestLeave(_ intent: VesselLeaveIntent, on simulator: NMEASimulator) -> VesselLeaveGate {
        if case .highlight(let id) = intent, id == highlightedID { return .allowed }
        if case .activate(let id) = intent, id == highlightedID { return .allowed }
        if hasUnsavedChanges(in: simulator) {
            switch commitEdits(on: simulator, refreshingDisplay: false) {
            case .saved:
                validationMessage = nil
            case .invalid:
                // Intermediate text never became a profile change. Leave reloads the last persisted profile.
                validationMessage = nil
            case .failed:
                return .blocked
            }
        }
        reveal(intent, on: simulator)
        return .allowed
    }

    /// Writes the current buffer when it is valid. Invalid text stays on screen and does not replace the stored profile.
    func persistValidEdits(on simulator: NMEASimulator) {
        guard isReloadingProfile == false, isPersistingEdits == false else { return }
        guard hasUnsavedChanges(in: simulator) else { return }
        isPersistingEdits = true
        defer { isPersistingEdits = false }
        switch commitEdits(on: simulator, refreshingDisplay: false) {
        case .saved:
            validationMessage = nil
        case .invalid(let message):
            validationMessage = message
            lastResult = .idle
        case .failed:
            validationMessage = nil
        }
    }

    @discardableResult
    func saveBuffer(on simulator: NMEASimulator) -> Bool {
        switch commitEdits(on: simulator, refreshingDisplay: true) {
        case .saved:
            validationMessage = nil
            return true
        case .invalid(let message):
            validationMessage = message
            lastResult = .failed(.invalidProfileData(message))
            return false
        case .failed:
            return false
        }
    }

    @discardableResult
    func createDefaultVessel(on simulator: NMEASimulator) -> VesselProfile? {
        let names = Set(simulator.vessels.map(\.name))
        var name = "Custom Vessel"
        var suffix = 2
        while names.contains(name) {
            name = "Custom Vessel \(suffix)"
            suffix += 1
        }
        reloadDepth += 1
        defer { reloadDepth -= 1 }
        guard let profile = createVessel(name: name, modelName: nil, constructionYear: nil, on: simulator) else {
            return nil
        }
        show(profile.id, on: simulator)
        return profile
    }

    private enum EditCommit {
        case saved
        case invalid(String)
        case failed
    }

    private func commitEdits(on simulator: NMEASimulator, refreshingDisplay: Bool) -> EditCommit {
        guard let profile = highlightedProfile(in: simulator) else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return .failed
        }
        let metadata: VesselEditableMetadata?
        if profile.origin == .custom {
            let trimmed = buffer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .invalid("A vessel name is required.")
            }
            guard case .value(let year) = buffer.parsedYear else {
                return .invalid("Construction year must be a whole number.")
            }
            if let year, !(1800...2100).contains(year) {
                return .invalid("Construction year must be from 1800 through 2100.")
            }
            switch buffer.editableMetadata(name: trimmed, year: year) {
            case .success(let value):
                metadata = value
            case .failure(let error):
                return .invalid(error.message)
            }
        } else {
            metadata = nil
        }
        switch buffer.sailRecords() {
        case .success(let sails):
            let saved = perform(on: simulator) {
                try simulator.saveProfileEdits(profile.id, metadata: metadata, inventory: sails)
                return true
            } != nil
            guard saved else { return .failed }
            if refreshingDisplay, let stored = highlightedProfile(in: simulator) {
                buffer = VesselEditBuffer(profile: stored)
            }
            return .saved
        case .failure(let error):
            return .invalid(error.message)
        }
    }

    @discardableResult
    func createVessel(
        name: String,
        modelName: String?,
        constructionYear: Int?,
        on simulator: NMEASimulator
    ) -> VesselProfile? {
        perform(on: simulator) {
            let profile = try simulator.createCustomVessel(
                name: name,
                modelName: modelName,
                constructionYear: constructionYear
            )
            highlightedID = profile.id
            return profile
        }
    }

    @discardableResult
    func saveMetadata(id: UUID, metadata: VesselEditableMetadata, on simulator: NMEASimulator) -> Bool {
        perform(on: simulator) {
            try simulator.updateCustomVessel(id, metadata: metadata)
            return true
        } != nil
    }

    @discardableResult
    func saveMetadata(
        id: UUID,
        name: String,
        modelName: String?,
        constructionYear: Int?,
        on simulator: NMEASimulator
    ) -> Bool {
        perform(on: simulator) {
            try simulator.updateCustomVessel(id, name: name, modelName: modelName, constructionYear: constructionYear)
            return true
        } != nil
    }

    @discardableResult
    func duplicateHighlighted(on simulator: NMEASimulator) -> VesselProfile? {
        guard let highlightedID else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return nil
        }
        return perform(on: simulator) {
            let copy = try simulator.duplicateVessel(highlightedID)
            self.highlightedID = copy.id
            return copy
        }
    }

    @discardableResult
    func deleteHighlighted(on simulator: NMEASimulator) -> Bool {
        guard let highlightedID else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return false
        }
        let deleted = perform(on: simulator) {
            try simulator.deleteCustomVessel(highlightedID)
            return true
        } != nil
        if deleted {
            self.highlightedID = nil
        }
        return deleted
    }

    func activateHighlighted(on simulator: NMEASimulator) {
        guard let highlightedID else {
            lastResult = .failed(.invalidProfileData("Select a vessel in the library first."))
            return
        }
        guard simulator.vesselStoreError == nil else {
            lastResult = .failed(simulator.vesselStoreError ?? .readFailure("The vessel library is not available."))
            return
        }
        guard simulator.vessels.contains(where: { $0.id == highlightedID }) else {
            lastResult = .failed(.missingProfile(highlightedID))
            return
        }
        simulator.selectVessel(highlightedID)
        if simulator.selectedVesselID == highlightedID {
            lastResult = .succeeded
        } else {
            lastResult = .failed(.writeFailure("The active vessel was not changed."))
        }
    }

    @discardableResult
    private func perform<T>(on simulator: NMEASimulator, _ body: () throws -> T) -> T? {
        if let vesselStoreError = simulator.vesselStoreError {
            lastResult = .failed(vesselStoreError)
            return nil
        }
        do {
            let value = try body()
            lastResult = .succeeded
            return value
        } catch let error as VesselProfileStoreError {
            lastResult = .failed(error)
            return nil
        } catch {
            lastResult = .failed(.writeFailure(error.localizedDescription))
            return nil
        }
    }

    private func highlightedProfile(in simulator: NMEASimulator) -> VesselProfile? {
        guard let highlightedID else { return nil }
        return simulator.vessels.first { $0.id == highlightedID }
    }

    private func reveal(_ intent: VesselLeaveIntent, on simulator: NMEASimulator) {
        switch intent {
        case .highlight(let id), .activate(let id), .duplicate(let id), .delete(let id), .rename(let id):
            if highlightedID != id {
                show(id, on: simulator)
            }
        case .create:
            break
        }
    }
}

enum VesselLeaveIntent: Equatable {
    case highlight(UUID)
    case create
    case duplicate(UUID)
    case delete(UUID)
    case rename(UUID)
    case activate(UUID)
}

enum VesselLeaveGate: Equatable {
    case allowed
    case blocked
}

struct VesselEditBuffer: Equatable {
    var name = ""
    var manufacturer = ""
    var modelName = ""
    var yearText = ""
    var sailNumber = ""
    var registration = ""
    var lengthOverall = ""
    var waterlineLength = ""
    var beam = ""
    var draft = ""
    var displacement = ""
    var foretriangleHeight = ""
    var foretriangleBase = ""
    var mainsailLuff = ""
    var mainsailFoot = ""
    var sails: [SailDraft] = []

    init() {}

    init(profile: VesselProfile) {
        name = profile.name
        manufacturer = profile.manufacturer ?? ""
        modelName = profile.modelName ?? ""
        yearText = profile.constructionYear.map(String.init) ?? ""
        sailNumber = profile.sailNumber ?? ""
        registration = profile.registration ?? ""
        lengthOverall = Self.displayMetres(profile.hull.lengthOverallMeters)
        waterlineLength = Self.displayMetres(profile.hull.waterlineLengthMeters)
        beam = Self.displayMetres(profile.hull.beamMeters)
        draft = Self.displayMetres(profile.hull.draftMeters)
        displacement = Self.displayKilograms(profile.hull.displacementKilograms)
        foretriangleHeight = Self.displayMetres(profile.rig.foretriangleHeightMeters)
        foretriangleBase = Self.displayMetres(profile.rig.foretriangleBaseMeters)
        mainsailLuff = Self.displayMetres(profile.rig.mainsailLuffMeters)
        mainsailFoot = Self.displayMetres(profile.rig.mainsailFootMeters)
        sails = profile.inventory.map(SailDraft.init(record:))
    }

    var signature: EditSignature {
        EditSignature(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            manufacturer: manufacturer.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            year: parsedYear,
            sailNumber: sailNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            registration: registration.trimmingCharacters(in: .whitespacesAndNewlines),
            lengthOverall: Self.token(lengthOverall),
            waterlineLength: Self.token(waterlineLength),
            beam: Self.token(beam),
            draft: Self.token(draft),
            displacement: Self.token(displacement),
            foretriangleHeight: Self.token(foretriangleHeight),
            foretriangleBase: Self.token(foretriangleBase),
            mainsailLuff: Self.token(mainsailLuff),
            mainsailFoot: Self.token(mainsailFoot),
            sails: sails.map(\.signature)
        )
    }

    var sailSignature: [SailDraft.Signature] {
        sails.map(\.signature)
    }

    func sailRecords() -> Result<[SailRecord], VesselProfileStoreError> {
        do {
            return .success(try sails.map { try $0.record() })
        } catch let error as VesselProfileStoreError {
            return .failure(error)
        } catch {
            return .failure(.writeFailure(error.localizedDescription))
        }
    }

    func editableMetadata(name: String, year: Int?) -> Result<VesselEditableMetadata, VesselProfileStoreError> {
        do {
            return .success(VesselEditableMetadata(
                name: name,
                manufacturer: manufacturer,
                modelName: modelName,
                constructionYear: year,
                sailNumber: sailNumber,
                registration: registration,
                hull: HullDimensions(
                    lengthOverallMeters: try measurement(lengthOverall, "Length overall", unit: "metres"),
                    waterlineLengthMeters: try measurement(waterlineLength, "Waterline length", unit: "metres"),
                    beamMeters: try measurement(beam, "Beam", unit: "metres"),
                    draftMeters: try measurement(draft, "Draft", unit: "metres"),
                    displacementKilograms: try measurement(displacement, "Displacement", unit: "kilograms")
                ),
                rig: RigDimensions(
                    foretriangleHeightMeters: try measurement(foretriangleHeight, "I", unit: "metres"),
                    foretriangleBaseMeters: try measurement(foretriangleBase, "J", unit: "metres"),
                    mainsailLuffMeters: try measurement(mainsailLuff, "P", unit: "metres"),
                    mainsailFootMeters: try measurement(mainsailFoot, "E", unit: "metres")
                )
            ))
        } catch let error as VesselProfileStoreError {
            return .failure(error)
        } catch {
            return .failure(.writeFailure(error.localizedDescription))
        }
    }

    enum ParsedYear: Equatable {
        case value(Int?)
        case invalid
    }

    enum MeasurementToken: Equatable {
        case empty
        case value(Double)
        case invalid(String)
    }

    var parsedYear: ParsedYear {
        let trimmed = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .value(nil) }
        guard let year = Int(trimmed) else { return .invalid }
        return .value(year)
    }

    static func displayMetres(_ value: Double?) -> String {
        guard let value else { return "" }
        return format(value, fractionDigits: 3)
    }

    static func displayKilograms(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = numberFormatter(fractionDigits: 3, pad: false)
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    static func token(_ text: String) -> MeasurementToken {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if isIncompleteDecimal(trimmed) { return .invalid(trimmed) }
        guard let value = parse(trimmed), value.isFinite else { return .invalid(trimmed) }
        return .value((value * 1_000_000).rounded() / 1_000_000)
    }

    static func isIncompleteDecimal(_ text: String) -> Bool {
        text.hasSuffix(".") || text.hasSuffix("e") || text.hasSuffix("E") || text.hasSuffix("+") || text.hasSuffix("-")
    }

    private func measurement(_ text: String, _ label: String, unit: String) throws -> Double? {
        switch Self.token(text) {
        case .empty:
            return nil
        case .invalid:
            throw VesselProfileStoreError.invalidProfileData("\(label) must be a number in \(unit).")
        case .value(let value):
            guard value > 0 else {
                throw VesselProfileStoreError.invalidProfileData("\(label) must be greater than zero.")
            }
            return value
        }
    }

    private static func parse(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        return formatter.number(from: text.trimmingCharacters(in: .whitespacesAndNewlines))?.doubleValue
    }

    private static func format(_ value: Double, fractionDigits: Int) -> String {
        numberFormatter(fractionDigits: fractionDigits, pad: true).string(from: NSNumber(value: value)) ?? ""
    }

    private static func numberFormatter(fractionDigits: Int, pad: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = pad ? fractionDigits : 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumIntegerDigits = 1
        return formatter
    }
}

struct EditSignature: Equatable {
    var name: String
    var manufacturer: String
    var modelName: String
    var year: VesselEditBuffer.ParsedYear
    var sailNumber: String
    var registration: String
    var lengthOverall: VesselEditBuffer.MeasurementToken
    var waterlineLength: VesselEditBuffer.MeasurementToken
    var beam: VesselEditBuffer.MeasurementToken
    var draft: VesselEditBuffer.MeasurementToken
    var displacement: VesselEditBuffer.MeasurementToken
    var foretriangleHeight: VesselEditBuffer.MeasurementToken
    var foretriangleBase: VesselEditBuffer.MeasurementToken
    var mainsailLuff: VesselEditBuffer.MeasurementToken
    var mainsailFoot: VesselEditBuffer.MeasurementToken
    var sails: [SailDraft.Signature]
}
