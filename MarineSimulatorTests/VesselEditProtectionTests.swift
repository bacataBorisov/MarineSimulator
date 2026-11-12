import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselEditProtectionTests {

    @Test
    func aCleanProfileChangesHighlightWithoutConfirmation() throws {
        let simulator = editSimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: nil, constructionYear: nil, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.name = "Skiff "
        #expect(session.hasUnsavedChanges(in: simulator) == false)

        let gate = session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator)
        #expect(gate == .allowed)
        #expect(session.isConfirmingUnsavedChanges == false)
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func dirtyNavigationSaveDiscardAndCancelKeepTheActiveVessel() throws {
        let simulator = editSimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.name = "Skiff II"
        session.buffer.modelName = "Two"
        #expect(session.hasUnsavedChanges(in: simulator))
        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .needsConfirmation)
        #expect(session.highlightedID == custom.id)
        #expect(session.isConfirmingUnsavedChanges)

        #expect(session.resolveUnsavedChanges(.cancel, on: simulator) == .stayed)
        #expect(session.highlightedID == custom.id)
        #expect(session.buffer.name == "Skiff II")
        #expect(session.buffer.modelName == "Two")
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff")
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        #expect(session.requestLeave(.duplicate(custom.id), on: simulator) == .needsConfirmation)
        #expect(session.highlightedID == custom.id)
        #expect(session.resolveUnsavedChanges(.cancel, on: simulator) == .stayed)
        #expect(session.buffer.name == "Skiff II")

        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .needsConfirmation)
        #expect(session.resolveUnsavedChanges(.discard, on: simulator) == .perform(.highlight(BuiltInVesselID.nimana)))
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        #expect(session.buffer.name == "Nimana")
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff")
        #expect(simulator.vessels.first { $0.id == custom.id }?.modelName == "One")
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        session.show(custom.id, on: simulator)
        session.buffer.name = "Skiff III"
        session.buffer.modelName = "Two"
        #expect(session.requestLeave(.highlight(BuiltInVesselID.extasy), on: simulator) == .needsConfirmation)
        #expect(session.resolveUnsavedChanges(.save, on: simulator) == .perform(.highlight(BuiltInVesselID.extasy)))
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff III")
        #expect(simulator.vessels.first { $0.id == custom.id }?.modelName == "Two")
        #expect(session.highlightedID == BuiltInVesselID.extasy)
        #expect(session.buffer.name == "Extasy")
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func invalidAndFailedSavesStayOnTheEditedProfile() throws {
        let simulator = editSimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.name = "Skiff II"
        session.buffer.yearText = "nope"
        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .needsConfirmation)
        #expect(session.resolveUnsavedChanges(.save, on: simulator) == .stayed)
        #expect(session.highlightedID == custom.id)
        #expect(session.buffer.name == "Skiff II")
        #expect(session.buffer.yearText == "nope")
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff")
        #expect(session.failureMessage == "Construction year must be a whole number.")
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        let store = RejectingEditStore()
        let persisted = editSimulator(store: store)
        let editing = VesselLibrarySession()
        let again = try #require(editing.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: persisted))
        editing.show(again.id, on: persisted)
        store.rejectWrites = true
        editing.buffer.modelName = "Kept"
        #expect(editing.requestLeave(.highlight(BuiltInVesselID.nimana), on: persisted) == .needsConfirmation)
        #expect(editing.resolveUnsavedChanges(.save, on: persisted) == .stayed)
        #expect(editing.highlightedID == again.id)
        #expect(editing.buffer.modelName == "Kept")
        #expect(persisted.vessels.first { $0.id == again.id }?.modelName == "One")
        #expect(editing.failureMessage?.contains("could not be saved") == true)
        #expect(persisted.selectedVesselID == BuiltInVesselID.extasy)
    }
}

private final class RejectingEditStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    var rejectWrites = false

    func loadDocument() throws -> VesselProfileDocument? { document }

    func saveDocument(_ document: VesselProfileDocument) throws {
        if rejectWrites {
            throw VesselProfileStoreError.writeFailure("disk full")
        }
        self.document = document
    }
}

private func editSimulator(store: (any VesselProfileStoring)? = nil) -> NMEASimulator {
    let suite = "VesselEdit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return NMEASimulator(userDefaults: defaults, vesselStore: store ?? InMemoryVesselProfileStore())
}
