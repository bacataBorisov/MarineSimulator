import AppKit
import SwiftUI

@MainActor
enum SimulatorCommandTarget {
    static weak var current: NMEASimulator?
}

struct MarineSimulatorCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .sidebar) {
            Button(SimulatorCommandTarget.current?.isTransmitting == true ? "Stop" : "Start") {
                toggleSimulation()
            }
            .disabled(SimulatorCommandTarget.current == nil)

            Button("Copy Console") {
                copyConsole()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(SimulatorCommandTarget.current == nil)
        }

        CommandGroup(after: .importExport) {
            Button("Export Settings…") {
                guard let sim = SimulatorCommandTarget.current else { return }
                SettingsDocumentController.exportSettings(from: sim)
            }
            Button("Import Settings…") {
                guard let sim = SimulatorCommandTarget.current else { return }
                SettingsDocumentController.importSettings(into: sim)
            }
        }
    }

    private func toggleSimulation() {
        guard let sim = SimulatorCommandTarget.current else { return }
        if sim.isTransmitting {
            sim.stopSimulation()
        } else {
            sim.startSimulation()
        }
    }

    private func copyConsole() {
        guard let sim = SimulatorCommandTarget.current else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sim.nmeaConsoleExportText(), forType: .string)
    }
}

