# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Step 1 performance/UI fixes (single shared `ConsolePanelView` across Dashboard and all Setup pages, `NSGlassEffectView` map re-center button, normalized `WindCompass` start/fold, `SidebarMaterialFlattener` guard, `GaugeMarkerCompass` stable IDs, `ExperimentDiagnosticsSession` sentence cache) passed user smoke tests and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged (Dashboard map host stays full-size behind `isHidden` off-dashboard so `MKMapView` stays warm; `MainView` owns the single shared `ConsolePanelView` across all destinations). Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Step 2 page-switching latency optimization (retaining remaining safe pages / reducing navigation work after user approval).
