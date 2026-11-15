# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Step A UI/HIG pass (`Wind`/`Compass`/`Hydro`/`GPS` on `DesignToken` + `SettingsCard`, `1080pt` window minimum, `900pt` `SentencePage` split breakpoint, inline `SensorEnablePrompt` buttons, compact `ConnectionStatusPill`, GPS scroll-wheel passthrough + `MKZoomControl`) passed user smoke tests and is committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, Diagnostics, Overview, Wind, Compass, Hydro, GPS, and Dashboard keep their retained AppKit hosts; `MainView` owns the single shared `ConsolePanelView` across all destinations. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Step B UI/HIG pass on `ExperimentDiagnosticsView` (`DesignToken` / `SettingsCard` / adaptive error rows / accessibility labels).
