# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). File-split cleanup (Steps 1–5), per-page scroll restoration, and Weather GPS-off glance hint + direct `Enable GPS` popover passed user smoke tests and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Add numeric input restriction / inline feedback on Boat Profile numeric fields (`Views/BoatProfileEditor.swift`, `Views/SailInventoryEditor.swift`).
2. Add atmospheric NMEA sentences (air temp, humidity, barometer).
3. Return to GPS `retainedMapResource`.
