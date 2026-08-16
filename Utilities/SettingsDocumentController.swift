import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsDocumentController {
    static let exportType = UTType.json

    static func exportSettings(from simulator: NMEASimulator) {
        let panel = NSSavePanel()
        panel.title = "Export Simulator Settings"
        panel.allowedContentTypes = [exportType]
        panel.nameFieldStringValue = "MarineSimulator-Settings.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try JSONEncoder().encode(simulator.makeSettingsSnapshotForExport())
                try data.write(to: url, options: .atomic)
            } catch {
                presentError("Export failed", error)
            }
        }
    }

    static func importSettings(into simulator: NMEASimulator) {
        let panel = NSOpenPanel()
        panel.title = "Import Simulator Settings"
        panel.allowedContentTypes = [exportType]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let settings = try JSONDecoder().decode(SimulatorSettings.self, from: data)
                simulator.applyImportedSettings(settings)
            } catch {
                presentError("Import failed", error)
            }
        }
    }

    private static func presentError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
