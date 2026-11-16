# Session Cache

Last updated: 2026-11-16

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Step M3-B (`PerformanceParameters` hidden polar factors, time-varying wind/course sweep, reference polar STW comparison, single-line NMEA output, tick-0 `SOG`/`COG` fix, `Diagnostics` input persistence, and unit tests) passed user smoke tests and is committed.

## Constraints

Direct single-chat workflow; user is external smoke-test verifier. `Manual` stays ephemeral; all other pages use retained AppKit hosts with one shared `ConsolePanelView` in `MainView`. Check local HIG docs before UI proposals.

## Next

1. Explain and implement proof-of-concept CSV export (`ExperimentOutputContract`) + offline polar-recovery test against a hidden degraded polar.
2. Draft the professor proposal plan with prototype evidence, then proceed to full M4 (JSON scenario library, CSV export workflow, replay tests).
