# Research roadmap

Status: **M3.4.3a adds Experiment Diagnostics for an isolated prepared run.** A normal session keeps the previous NMEA. Do not start scenario files, current motion, dataset export, or charts without a new task. See `.agent/architecture/implementation-status.md`. The October 2026 audit predates the truth split.

The app stays a general NMEA 0183 UDP/TCP simulator. Research features stay off unless a scenario turns them on.

## Now

M1 truth split is in `SimulationState` and `SimulationEngine.tickSimulation`. Design note: `guides/m1-truth-layers.md`. Audit: `investigations/research-readiness-2026-10.md`.

## Next, in order

1. **M1 — Truth split.** Environment truth, vessel truth, sensor readings, NMEA snapshot. Sensor noise must not move the boat. Existing sentences and the 20 Hz / 10 Hz split stay.
2. **M2 — Performance dynamics.** Keep the First 40.7 table. Add a polar abstraction, optional first-order speed, maneuver speed loss. Baseline vs hidden polar, hidden parameters not on the wire.
3. **M3 — Environment and sensors.** Seeded manual evolution, an in-memory scenario, and hidden-polar speed are implemented. Sensor availability does not move the boat. A prepared experiment publishes measured wind, log speed, gyro heading, and compass heading. A normal session does not. Current is declared and does not move the boat. Wire faults in `SentenceScheduler` stay.
4. **M4 — Experiments.** JSON scenarios, CSV export of truth vs measurements, replay tests.
5. **M5 — Scientific review.** Document what is consistent, what is repeatable, and what is not validated against a real boat.

## Parked

NMEA 2000, CFD, 6-DOF, sail-by-sail aerodynamics.
