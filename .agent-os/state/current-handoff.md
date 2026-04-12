# Current handoff

_Updated: 2026-04-10 03:48 UTC_

## Current work

- Latest completed feature: live weather V1.
- `NMEASimulator` now supports `manual` vs `liveWeather` source mode, persists the selection, and can fetch wind plus sea-surface temperature from Open-Meteo using the current GPS coordinates.
- `ConfigurationView` now exposes weather source selection, refresh policy, provider status, and manual refresh.

## Repo state

- Last scan id: 1
- Working tree is dirty in the latest session, including `.agent-os/` handoff files, several docs, and `Views/Dashboard/BoatMapPreview.swift`.

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

- `.agent-os/context/cache.md`
- `Docs/CompletedTasks.md`
- `Docs/CurrentTasks.md`
- `Docs/InstructionManual.md`
- `Docs/ManualTestChecklist.md`
- `Docs/ProjectOverview.md`

## Open decisions

- Whether the preview-only crash for `Views/Dashboard/BoatMapPreview.swift` needs immediate investigation.
- Whether the next weather iteration should add more environmental values/current effects or pause weather work and return to protocol fidelity/manual expansion.

## Risks

- Xcode preview rendering still reports a possible app crash for `Views/Dashboard/BoatMapPreview.swift`, even though compile-time diagnostics are clean and the project builds successfully.
- Future protocol or transport changes may require another manual interoperability pass even though the current checklist has been accepted.
- Live weather depends on network availability and provider quality; V1 currently does not model coastal current/tide effects.

## Recommended next actions

- Manually verify live weather in the running app with real GPS coordinates and provider responses.
- Decide whether to extend weather realism next or return to the remaining fidelity/manual tasks in `Docs/CurrentTasks.md`.
- Manually verify the floating map toolbar placement with the left controls rail, trailing instruments rail, and console expanded together if that UI tweak has not been visually confirmed yet.
- Investigate the preview-only crash only if more dashboard preview iteration is needed next.
- Run `agentos-scan scan` after code changes.
- Run `agentos export` (default profile **deep**) before a long agent task; use `--profile normal` for a smaller pack.
