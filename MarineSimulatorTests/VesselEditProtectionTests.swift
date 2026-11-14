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
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func validEditsAutosaveWithoutAPromptAndLeaveTheActiveVesselAlone() throws {
        let simulator = editSimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: simulator))
        session.show(custom.id, on: simulator)
        session.buffer.name = "Skiff II"
        session.buffer.modelName = "Two"
        session.persistValidEdits(on: simulator)
        #expect(session.hasUnsavedChanges(in: simulator) == false)
        #expect(session.lastChangeSucceeded)
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff II")
        #expect(simulator.vessels.first { $0.id == custom.id }?.modelName == "Two")
        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .allowed)
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        #expect(session.buffer.name == "Nimana")
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        session.show(custom.id, on: simulator)
        #expect(session.buffer.name == "Skiff II")
        #expect(session.buffer.modelName == "Two")
        session.buffer.name = "Skiff III"
        session.persistValidEdits(on: simulator)
        #expect(session.requestLeave(.highlight(BuiltInVesselID.extasy), on: simulator) == .allowed)
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff III")
        #expect(session.highlightedID == BuiltInVesselID.extasy)
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
        session.persistValidEdits(on: simulator)
        #expect(session.highlightedID == custom.id)
        #expect(session.buffer.name == "Skiff II")
        #expect(session.buffer.yearText == "nope")
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff")
        #expect(session.validationMessage == "Construction year must be a whole number.")
        #expect(session.lastChangeSucceeded == false)
        #expect(session.requestLeave(.highlight(BuiltInVesselID.nimana), on: simulator) == .allowed)
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        #expect(simulator.vessels.first { $0.id == custom.id }?.name == "Skiff")
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        let store = RejectingEditStore()
        let persisted = editSimulator(store: store)
        let editing = VesselLibrarySession()
        let again = try #require(editing.createVessel(name: "Skiff", modelName: "One", constructionYear: 2020, on: persisted))
        editing.show(again.id, on: persisted)
        store.rejectWrites = true
        editing.buffer.modelName = "Kept"
        editing.persistValidEdits(on: persisted)
        #expect(editing.requestLeave(.highlight(BuiltInVesselID.nimana), on: persisted) == .blocked)
        #expect(editing.highlightedID == again.id)
        #expect(editing.buffer.modelName == "Kept")
        #expect(persisted.vessels.first { $0.id == again.id }?.modelName == "One")
        #expect(editing.failureMessage?.contains("could not be saved") == true)
        #expect(editing.lastChangeSucceeded == false)
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
