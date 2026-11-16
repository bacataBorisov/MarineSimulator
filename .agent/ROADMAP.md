# Research roadmap

Status: **M3 core and proof-of-concept prototypes complete; M4 awaiting professor proposal review.** Do not start the M4 JSON scenario library or research-studio UI without explicit approval. See `.agent/architecture/implementation-status.md` for verified code reality. The October 2026 audit in `.agent/investigations/research-readiness-2026-10.md` predates the truth split.

The app stays a general NMEA 0183 UDP/TCP simulator. Research features stay off unless a scenario or the isolated Diagnostics page turns them on.

## Completed

1. **M1 — Truth split.** `EnvironmentTruth` and `VesselTruth` separated from instrument readings and `SimulationSnapshot`; sensor switches/noise never move the boat; 20 Hz physics / 10 Hz UI split preserved.
2. **M2 — Performance dynamics.** First 40.7 Farr #354 polar table, `PolarModel` baseline vs. `hiddenPolarOverride`, `PerformanceParameters` (instant or first-order speed lag, hidden multipliers, maneuver speed retention), `VesselProfile` library with `HullDimensions`, `RigDimensions`, and `SailInventory`.
3. **M3 — Environment, sensors, and PoC export.**
   - Seeded manual evolution (`ExperimentRandomGenerator`), in-memory `ExperimentScenario` + `ExperimentScenarioRunner`, and `ExperimentSensorModel` (bias + uniform noise on AWS, AWA, STW, true heading, and magnetic compass).
   - `ExperimentCurrentProgram` set/drift vector wired into `EnvironmentTruth` and `SimulationEngine.simulatedCurrent` / `simulatedMovement` (separating SOG/COG from STW/HDT, including tick-0 initialization).
   - `PerformanceParameters` hidden polar multipliers, deterministic sinusoidal `ExperimentWindProgram` (direction swing, speed amplitude, period), and continuous `courseSweepDegreesPerSecond` exposed in `ExperimentDiagnosticsView` with persisted inputs.
   - Proof-of-concept `ExperimentDatasetRecorder` / CSV export (`Export CSV…` adhering to `ExperimentOutputContract` without truth leakage, plus `Export Truth…` for validation), verified offline polar recovery (`PolarRecoveryProofOfConceptTests`), and geometry-only cold-start VPP prior (`ParametricPolarGenerator` + `ParametricPolarComparisonTests`).

## Ahead, in order

4. **M4 — Experiments & Research Integration.**
   - Professor proposal approval on thesis methodology and scope.
   - Persistent JSON scenario library, angle-dependent polar degradation (upwind vs. downwind), repeatable batch replay tests, and sensor delay/drift/dropout.
   - `PolarResearchCore` / `PolarResearchStudio` interface (or offline evaluation pipeline): tabular & polar-plot comparison (manufacturer vs. synthetic vs. adapted), 2D `(TWS, TWA)` smoothing, and STW-bias calibration against GNSS (`SOG/COG`).
   - `BoatProfile.nimana` ORC polar integration (`Resources/ReferenceDocuments/Nimana/ORC_2026_009-26.pdf`).
5. **M5 — Scientific review.** Document model consistency, seed repeatability, identifiability limits, and any empirical validation against real Extasy log data without overclaiming hull calibration.

## Parked

NMEA 2000, CFD, 6-DOF hydrodynamics, sail-by-sail aerodynamics.
