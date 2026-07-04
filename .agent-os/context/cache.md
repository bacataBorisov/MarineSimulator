# Session Cache

Last updated: 2026-07-04

## Current Objective

Fix UI lag during active NMEA transmission while preserving live slider adjustment and dead-reckoning correctness.

## Product State

- Fast transmit loop runs on a dedicated `DispatchSourceTimer` / `simulationQueue` (20 Hz), not the main run loop.
- `TransmitRuntime` holds authoritative sim state off-main; UI-bound fields batch-apply on main each cycle.
- Console output is throttled (~100 ms) via `consoleRecordBuffer` + `consoleDisplayGeneration`.
- Redundant `endpointStatuses` writes skipped when level/message unchanged.
- Dead-reckoning tests still pass (`gpsPositionFollowsGyroSetpointNotMagneticCenter`, etc.).

## Next

1. Manual UI sanity check: sliders remain responsive during 30–60 s transmit.
2. NMEA fidelity / overlay work per `Docs/CurrentTasks.md`.

## Notes

- Root cause was main-thread 20 Hz `Timer` + per-sentence `@Observable` churn (console rows, transport status).
- Avoid `DispatchQueue.main.sync` from the simulation queue (deadlock with `stopSimulation`).
