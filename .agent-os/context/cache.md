# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). File-split cleanup (Steps 1–5) and per-page scroll-position restoration passed focused tests and user smoke tests, and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Add GPS-off glance hint to `WeatherModeToolbarPill` (`Views/MainWindowToolbar.swift`).
2. Add numeric input restriction / inline feedback on Boat Profile numeric fields (`Views/BoatProfileEditor.swift`).
3. Add atmospheric NMEA sentences (air temp, humidity, barometer).
4. Return to GPS `retainedMapResource`.
