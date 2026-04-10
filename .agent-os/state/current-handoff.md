# Current handoff

_Updated: 2026-04-10 02:52 UTC_

## Current work

- Session bootstrap completed.
- Required Agent OS context files were re-read successfully in order.
- No active product, UI, or engine task is in progress yet.

## Repo state

- Last scan id: 1

## Relevant files (indexed, latest scan)

- `.gitignore`
- `AGENTS.md`
- `AGENT_OS.md`
- `App/MarineSimulator.swift`
- `Docs/CompletedTasks.md`
- `Docs/CurrentTasks.md`
- `Docs/FutureTasks.md`
- `Docs/InstructionManual.md`
- `Docs/ManualTestChecklist.md`
- `Docs/ProjectOverview.md`
- `LICENSE`
- `MarineSimulator.xcodeproj/xcuserdata/bacataborisov.xcuserdatad/xcschemes/xcschememanagement.plist`
- `MarineSimulatorTests/NMEASimulatorEngineTests.swift`
- `MarineSimulatorUITests/MarineSimulatorUITests.swift`
- `MarineSimulatorUITests/MarineSimulatorUITestsLaunchTests.swift`
- `Model/GPSData.swift`
- `Model/OutputEndpoint.swift`
- `Model/SensorToggleStates.swift`
- `Model/SentenceToggleStates.swift`
- `Model/SimulatedValue.swift`
- `Model/SimulationSnapshot.swift`
- `Model/SimulatorSettings.swift`
- `NMEA/NMEASimulator+FormattedValues.swift`
- `NMEA/NMEASimulator+SentenceBuilder.swift`
- `NMEA/NMEASimulator+WindCalculations.swift`
- `NMEA/NMEASimulator.swift`
- `NMEASimulator/Assets.xcassets/AccentColor.colorset/Contents.json`
- `NMEASimulator/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `NMEASimulator/Assets.xcassets/Contents.json`
- `NMEASimulator/Assets.xcassets/dial_gauge_end.colorset/Contents.json`
- `NMEASimulator/Assets.xcassets/dial_gauge_start.colorset/Contents.json`
- `NMEASimulator/Item.swift`
- `NMEASimulator/Preview Content/Preview Assets.xcassets/Contents.json`
- `NMEASimulator/Preview Content/PreviewData.swift`
- `Networking/TCPClient.swift`
- `Networking/UDPClient.swift`
- `README.md`
- `Utilities/AppConstants.swift`
- `Utilities/FormatKit.swift`
- `Utilities/MathUtilities.swift`

## Relevant docs

- `.agent-os/context/begin-chat.md`
- `.agent-os/context/cache.md`
- `.agent-os/context/project-memory.md`
- `.agent-os/context/open-questions.md`
- `Docs/CurrentTasks.md`
- `Docs/ManualTestChecklist.md`

## Open decisions

- None yet.

## Risks

- None yet.

## Recommended next actions

- Wait for the user to assign the first product/code task.
- Inspect only the relevant files for that task before editing.
- Run `agentos-scan scan` after code changes.
- Run `agentos export --profile=normal` before a long agent task.
