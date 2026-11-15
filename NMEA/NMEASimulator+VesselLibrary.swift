import Foundation

extension NMEASimulator {

    // MARK: - Vessel Library

    static func makeVesselStore(userDefaults: UserDefaults) -> any VesselProfileStoring {
        if userDefaults === UserDefaults.standard {
            return FileVesselProfileStore.applicationSupport()
        }
        return InMemoryVesselProfileStore()
    }

    var vesselAllowsSimulation: Bool {
        vesselStoreError == nil && {
            switch activeVesselState {
            case .resolved, .none:
                return true
            case .unresolved:
                return false
            }
        }()
    }

    var vesselAllowsBoatFeatures: Bool {
        vesselStoreError == nil && {
            if case .resolved = activeVesselState { return true }
            return false
        }()
    }

    var activeVesselName: String {
        switch activeVesselState {
        case .resolved(let id):
            return vesselRepository.profile(id: id)?.name ?? "Vessel"
        case .none:
            return "No boat"
        case .unresolved:
            return "No vessel"
        }
    }

    var activeVesselSummary: String {
        if let vesselStoreError {
            return "Vessel profiles could not be read (\(vesselStoreError)). The saved file was left in place."
        }
        switch activeVesselState {
        case .resolved(let id):
            return vesselRepository.profile(id: id)?.summary ?? "Select a vessel."
        case .none:
            return "Simulating raw instruments without a boat profile."
        case .unresolved(let storedReference):
            if storedReference.isEmpty {
                return "Select a vessel. The saved vessel was not found."
            }
            return "Select a vessel. Saved reference \(storedReference) was not found."
        }
    }

    var selectedVesselID: UUID? {
        if case .resolved(let id) = activeVesselState { return id }
        return nil
    }

    var persistedVesselReference: String {
        switch activeVesselState {
        case .resolved(let id):
            return id.uuidString
        case .none:
            return Self.noVesselReference
        case .unresolved(let storedReference):
            return storedReference
        }
    }

    private static let noVesselReference = "none"

    func selectVessel(_ id: UUID) {
        guard vesselStoreError == nil, let profile = vesselRepository.profile(id: id) else { return }
        isApplyingVesselSelection = true
        activeVesselState = .resolved(id)
        boatProfile = profile.sailingKey
        isApplyingVesselSelection = false
        adoptHoistedSails()
        persistSettingsIfNeeded()
    }

    func clearSelectedVessel() {
        guard vesselStoreError == nil else { return }
        isApplyingVesselSelection = true
        activeVesselState = .none
        boatProfile = .nimana
        isApplyingVesselSelection = false
        if boatSpeedMode != .manual {
            boatSpeedMode = .manual
        }
        if activeManeuver != nil || isTackInProgress {
            cancelManeuver()
        }
        adoptHoistedSails()
        persistSettingsIfNeeded()
    }

    @discardableResult
    func createCustomVessel(name: String, modelName: String? = nil, constructionYear: Int? = nil) throws -> VesselProfile {
        let profile = try vesselRepository.createCustomVessel(name: name, modelName: modelName, constructionYear: constructionYear)
        vessels = vesselRepository.profiles
        return profile
    }

    func renameVessel(_ id: UUID, to name: String) throws {
        try vesselRepository.renameVessel(id, to: name)
        vessels = vesselRepository.profiles
    }

    func updateCustomVessel(_ id: UUID, name: String, modelName: String?, constructionYear: Int?) throws {
        try vesselRepository.updateCustomVessel(id, name: name, modelName: modelName, constructionYear: constructionYear)
        vessels = vesselRepository.profiles
    }

    func updateCustomVessel(_ id: UUID, metadata: VesselEditableMetadata) throws {
        try vesselRepository.updateCustomVessel(id, metadata: metadata)
        vessels = vesselRepository.profiles
    }

    func saveProfileEdits(_ id: UUID, metadata: VesselEditableMetadata?, inventory: [SailRecord]) throws {
        try vesselRepository.saveProfileEdits(id, metadata: metadata, inventory: inventory)
        vessels = vesselRepository.profiles
        if selectedVesselID == id {
            reconcileHoistedSailsWithActiveInventory()
        }
    }

    func replaceActiveSails(_ id: UUID, with selection: ActiveSailSelection) throws {
        try vesselRepository.replaceActiveSails(id, with: selection)
        vessels = vesselRepository.profiles
    }

    /// Copies the active vessel's saved sail selection into the runtime hoisted-sail record.
    /// Called when the active vessel changes, at launch, and when the selection becomes unresolved.
    func adoptHoistedSails() {
        if let id = selectedVesselID, let profile = vesselRepository.profile(id: id) {
            sailConfiguration = profile.activeSails.runtimeConfiguration
        } else {
            sailConfiguration = SailConfiguration()
        }
        publishHoistedConfiguration()
    }

    /// Session hoist. Does not write the vessel's saved selection.
    func setHoistedSails(_ selection: ActiveSailSelection) throws {
        guard let id = selectedVesselID, let profile = vesselRepository.profile(id: id) else {
            throw VesselProfileStoreError.invalidProfileData("Select a vessel before changing hoisted sails.")
        }
        var selection = selection
        let previousMain = sailConfiguration.mainSailID
        if selection.mainsailID?.uuidString != previousMain {
            selection.mainsailReef = Self.reefFitting(selection.mainsailReef, mainsail: profile.inventory.first { $0.id == selection.mainsailID })
        }
        if selection.mainsailID == nil {
            selection.mainsailReef = .full
        }
        try VesselProfileRepository.validateActiveSails(selection, inventory: profile.inventory)
        sailConfiguration = selection.runtimeConfiguration
        publishHoistedConfiguration()
    }

    /// Drops hoisted sails that are no longer in the active inventory. Other hoisted slots stay.
    func reconcileHoistedSailsWithActiveInventory() {
        guard let id = selectedVesselID, let profile = vesselRepository.profile(id: id) else {
            sailConfiguration = SailConfiguration()
            publishHoistedConfiguration()
            return
        }
        var selection = ActiveSailSelection(
            mainsailID: sailConfiguration.mainSailID.flatMap(UUID.init(uuidString:)),
            headsailID: sailConfiguration.headsailID.flatMap(UUID.init(uuidString:)),
            downwindSailID: sailConfiguration.downwindSailID.flatMap(UUID.init(uuidString:)),
            mainsailReef: sailConfiguration.mainsailReef
        )
        selection = selection.clearingSails(absentFrom: profile.inventory)
        if let mainID = selection.mainsailID {
            selection.mainsailReef = Self.reefFitting(selection.mainsailReef, mainsail: profile.inventory.first { $0.id == mainID })
        }
        sailConfiguration = selection.runtimeConfiguration
        publishHoistedConfiguration()
    }

    private static func reefFitting(_ reef: ReefStep, mainsail: SailRecord?) -> ReefStep {
        guard let count = mainsail?.mainsail?.reefCount else { return reef }
        let used: Int
        switch reef {
        case .full: used = 0
        case .reef1: used = 1
        case .reef2: used = 2
        case .reef3: used = 3
        }
        return used > count ? .full : reef
    }

    /// Makes the current hoist and vessel the observation snapshot, including a running transmit state.
    func publishHoistedConfiguration() {
        vesselObservation.sailConfiguration = sailConfiguration
        vesselObservation.referenceProfile = boatProfile
        syncInputMirror()
        let sails = sailConfiguration
        let reference = boatProfile
        let publish = {
            self.transmitRuntime?.sailConfiguration = sails
            self.transmitRuntime?.vesselObservation.sailConfiguration = sails
            self.transmitRuntime?.vesselObservation.referenceProfile = reference
        }
        if DispatchQueue.getSpecific(key: Self.simulationQueueMarker) != nil {
            publish()
        } else {
            simulationQueue.sync(execute: publish)
        }
    }

    @discardableResult
    func duplicateVessel(_ id: UUID) throws -> VesselProfile {
        let copy = try vesselRepository.duplicateVessel(id)
        vessels = vesselRepository.profiles
        return copy
    }

    func deleteCustomVessel(_ id: UUID) throws {
        try vesselRepository.deleteCustomVessel(id)
        vessels = vesselRepository.profiles
        if case .resolved(let active) = activeVesselState, active == id {
            isApplyingVesselSelection = true
            activeVesselState = .unresolved(storedReference: id.uuidString)
            boatProfile = .nimana
            isApplyingVesselSelection = false
            if isTransmitting || simulationTimer != nil {
                stopSimulation()
            }
            adoptHoistedSails()
            persistSettingsIfNeeded()
        }
    }

    func applyStoredVesselSelection(_ settings: SimulatorSettings) {
        if vesselStoreError != nil {
            let reference = settings.vesselSelectionWasStored ? (settings.activeVesselID ?? "") : FileVesselProfileStore.fileName
            activeVesselState = .unresolved(storedReference: reference)
            isApplyingVesselSelection = true
            boatProfile = .nimana
            isApplyingVesselSelection = false
            return
        }
        guard settings.vesselSelectionWasStored else {
            activeVesselState = .resolved(BuiltInVesselID.extasy)
            isApplyingVesselSelection = true
            boatProfile = .beneteauFirst407
            isApplyingVesselSelection = false
            return
        }
        let raw = settings.activeVesselID ?? ""
        if raw == Self.noVesselReference {
            activeVesselState = .none
            isApplyingVesselSelection = true
            boatProfile = .nimana
            isApplyingVesselSelection = false
        } else if let id = UUID(uuidString: raw), vesselRepository.profile(id: id) != nil {
            activeVesselState = .resolved(id)
            isApplyingVesselSelection = true
            boatProfile = vesselRepository.profile(id: id)?.sailingKey ?? .nimana
            isApplyingVesselSelection = false
        } else {
            activeVesselState = .unresolved(storedReference: raw)
            isApplyingVesselSelection = true
            boatProfile = .nimana
            isApplyingVesselSelection = false
        }
    }
}
