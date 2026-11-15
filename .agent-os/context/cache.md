# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). File-split cleanup (Steps 1–5), per-page scroll restoration, Weather GPS-off glance hint, Boat numeric-field UX, and atmospheric NMEA sentences (`MDA` & `XDR`) passed user smoke tests and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Return to GPS `retainedMapResource`.
