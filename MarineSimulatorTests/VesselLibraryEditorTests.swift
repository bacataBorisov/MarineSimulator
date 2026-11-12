import Foundation
import Testing
@testable import MarineSimulator

@Suite(.serialized)
struct VesselLibraryEditorTests {

    @Test
    func createEditAndDuplicateKeepIdentityAndLeaveTheOriginalAlone() throws {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        let created = try #require(session.createVessel(name: "  Skiff  ", modelName: "Custom 28", constructionYear: 2024, on: simulator))
        #expect(session.lastChangeSucceeded)
        #expect(created.name == "Skiff")
        #expect(created.modelName == "Custom 28")
        #expect(created.constructionYear == 2024)
        #expect(created.performance == VesselProfile.Performance.none)
        #expect(created.origin == .custom)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(session.highlightedID == created.id)

        let saved = session.saveMetadata(id: created.id, name: "Skiff II", modelName: "Custom 29", constructionYear: 2025, on: simulator)
        #expect(saved)
        let edited = try #require(simulator.vessels.first { $0.id == created.id })
        #expect(edited.id == created.id)
        #expect(edited.name == "Skiff II")
        #expect(edited.modelName == "Custom 29")
        #expect(edited.performance == VesselProfile.Performance.none)

        session.highlight(BuiltInVesselID.extasy)
        let extasyCopy = try #require(session.duplicateHighlighted(on: simulator))
        #expect(extasyCopy.id != BuiltInVesselID.extasy)
        #expect(extasyCopy.name == "Extasy Copy")
        #expect(extasyCopy.performance == VesselProfile.Performance.none)
        #expect(extasyCopy.origin == .custom)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.extasy }?.performance == .farrDesign354)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(session.highlightedID == extasyCopy.id)

        session.highlight(created.id)
        let customCopy = try #require(session.duplicateHighlighted(on: simulator))
        #expect(customCopy.id != created.id)
        #expect(customCopy.performance == VesselProfile.Performance.none)
        #expect(simulator.vessels.first { $0.id == created.id }?.name == "Skiff II")
    }

    @Test
    func builtInProfilesStayProtectedAndHighlightingDoesNotActivate() {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        session.highlight(BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(session.highlightedID == BuiltInVesselID.nimana)

        #expect(session.saveMetadata(id: BuiltInVesselID.nimana, name: "Other", modelName: nil, constructionYear: nil, on: simulator) == false)
        #expect(session.lastChangeSucceeded == false)
        #expect(simulator.vessels.first { $0.id == BuiltInVesselID.nimana }?.name == "Nimana")
        #expect(session.deleteHighlighted(on: simulator) == false)
        #expect(simulator.vessels.contains { $0.id == BuiltInVesselID.nimana })
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
    }

    @Test
    func deletingTheActiveCustomVesselRequiresAnExplicitReplacement() throws {
        let simulator = librarySimulator()
        let session = VesselLibrarySession()
        let custom = try #require(session.createVessel(name: "Skiff", modelName: nil, constructionYear: nil, on: simulator))
        session.activateHighlighted(on: simulator)
        #expect(simulator.selectedVesselID == custom.id)

        #expect(session.deleteHighlighted(on: simulator))
        #expect(simulator.selectedVesselID == nil)
        #expect(simulator.activeVesselName == "No vessel")
        #expect(simulator.activeVesselSummary.contains(custom.id.uuidString))
        #expect(simulator.vesselAllowsSimulation == false)
        if case .unresolved(let reference) = simulator.activeVesselState {
            #expect(reference == custom.id.uuidString)
        } else {
            Issue.record("Expected the deleted id to stay unresolved")
        }

        session.highlight(BuiltInVesselID.extasy)
        #expect(simulator.selectedVesselID == nil)
        session.activateHighlighted(on: simulator)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        #expect(simulator.vesselAllowsSimulation)
    }

    @Test
    func aFailedWriteIsNotReportedAsSavedAndTheDashboardUsesTheSameActiveVessel() throws {
        let store = RejectingVesselStore()
        let defaults = isolatedLibraryDefaults()
        let simulator = NMEASimulator(userDefaults: defaults, vesselStore: store)
        let session = VesselLibrarySession()
        store.rejectWrites = true
        let before = simulator.vessels.map(\.id)
        let created = session.createVessel(name: "Skiff", modelName: "X", constructionYear: 2020, on: simulator)
        #expect(created == nil)
        #expect(session.lastChangeSucceeded == false)
        #expect(session.failureMessage?.contains("could not be saved") == true)
        #expect(simulator.vessels.map(\.id) == before)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)

        store.rejectWrites = false
        session.highlight(BuiltInVesselID.nimana)
        #expect(simulator.selectedVesselID == BuiltInVesselID.extasy)
        session.activateHighlighted(on: simulator)
        #expect(simulator.selectedVesselID == BuiltInVesselID.nimana)
        #expect(session.highlightedID == BuiltInVesselID.nimana)
        let restored = NMEASimulator(userDefaults: defaults, vesselStore: store)
        #expect(restored.selectedVesselID == BuiltInVesselID.nimana)
    }
}

private final class RejectingVesselStore: VesselProfileStoring {
    var document: VesselProfileDocument?
    var rejectWrites = false

    func loadDocument() throws -> VesselProfileDocument? {
        document
    }

    func saveDocument(_ document: VesselProfileDocument) throws {
        if rejectWrites {
            throw VesselProfileStoreError.writeFailure("disk full")
        }
        self.document = document
    }
}

private func librarySimulator() -> NMEASimulator {
    NMEASimulator(userDefaults: isolatedLibraryDefaults(), vesselStore: InMemoryVesselProfileStore())
}

private func isolatedLibraryDefaults() -> UserDefaults {
    let suite = "VesselLibrary.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
