# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). File-split cleanup (Steps 1–5), per-page scroll restoration, Weather GPS-off glance hint, and Boat Profile numeric-field focus/popover validation passed user smoke tests and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Add atmospheric NMEA sentences (air temp, humidity, barometer).
2. Return to GPS `retainedMapResource`.
