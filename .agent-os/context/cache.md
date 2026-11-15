# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). File-split audit Steps 1–5 are complete and committed (zero production files over 1,000 lines).

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Fix per-page last scroll-position restoration (`Views/ConsoleScrollTracking.swift`).
2. Add GPS-off glance hint to `WeatherModeToolbarPill` (`Views/MainWindowToolbar.swift`).
3. Add numeric input filtering / inline feedback on Boat Profile Hull/Rig/Year fields (`Views/BoatProfileEditor.swift`).
4. Add atmospheric NMEA sentences (air temp, humidity, barometer).
5. Return to GPS `retainedMapResource`.
