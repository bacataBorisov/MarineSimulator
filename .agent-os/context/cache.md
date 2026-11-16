# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Step M3-A (current set/drift motion in `SimulationEngine` + `ExperimentDiagnosticsView` controls/UI polish) passed user smoke tests and is committed.

## Constraints

Direct single-chat workflow; user is external smoke-test verifier. `Manual` stays ephemeral; all other pages use retained AppKit hosts with one shared `ConsolePanelView` in `MainView`. Check local HIG docs before UI proposals.

## Next

1. Step M3-B: expose `PerformanceParameters` (hidden hull/sail/trim/sea-state factors) + time-varying wind/heading sweep in `ExperimentScenario` / `Diagnostics` for the proof-of-concept experiment.
2. Proof-of-concept CSV export + polar recovery check, then draft the plan for professor approval, then M4.
