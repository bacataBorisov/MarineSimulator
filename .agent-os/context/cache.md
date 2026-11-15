# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Step B UI/HIG pass (`ExperimentDiagnosticsView` on `DesignToken` + `SettingsCard`, adaptive `ViewThatFits` error/control rows, focus-loss commit, `FormTextInputMode` input filtering + popover validation) passed user smoke tests and is committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, Diagnostics, Overview, Wind, Compass, Hydro, GPS, and Dashboard keep their retained AppKit hosts; `MainView` owns the single shared `ConsolePanelView` across all destinations. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Await user direction (Keyboard/VoiceOver check, custom proprietary NMEA sentences / new sentences, or M3/M4 research roadmap).
