# Session Cache

Last updated: 2026-11-14

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly without subagents or unrequested regression tests, user smoke-tests). Dashboard Heading controls (`Compass` live readout + `Gyro Compass (True)` + `Magnetic Compass`), `"No Boat (Instruments Only)"` mode (`ActiveVesselState.none`), and symmetric left-rail header padding passed user smoke test and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages. Do not add subagent handoffs or new regression tests unless explicitly asked. The user is the external verifier for runtime smoke tests.

## Next

1. Fix per-page last scroll-position restoration.
2. Check Dashboard right rail (`TrailingSidePanel`) or remaining UI polish if requested.
3. Return to GPS `retainedMapResource`.
