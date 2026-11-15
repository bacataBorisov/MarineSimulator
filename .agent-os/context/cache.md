# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Step 2 UI/performance pass (retained Sentence/Diagnostics/GPS hosts, retained `DashboardDocksHost` with center hit-test passthrough, split `SidebarColumnList`/`MainDetailColumn`, stable `MainWindowToolbar`, persisted Dashboard/GPS map cameras + `gpsData` stop/quit flush, `DeferredNumericField` & GPS warning fixes) passed user smoke tests and is committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, Diagnostics, Overview, Wind, Compass, Hydro, GPS, and Dashboard keep their retained AppKit hosts; `MainView` owns the single shared `ConsolePanelView` across all destinations. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Await user direction (deferred: runtime VoiceOver/keyboard checks, shared master-detail, custom proprietary NMEA sentence builder, or M4 experiment features).
