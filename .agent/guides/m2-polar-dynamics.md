# M2 plan — polar performance and vessel dynamics

Status: **implemented, waiting for acceptance.** Do not start Milestone 3.

`PolarModel` delegates to the existing `BoatProfile` interpolation. The First 40.7 table was not moved. Reference and hidden polars both follow the selected boat profile unless `hiddenPolarOverride` is set. That override, the performance factors, and scheduled changes stay on `SimulationState`. `VesselObservation` exposes the reference profile, maneuver phase, maneuver kind, and sail configuration. Sail configuration does not change speed. `SailPerformanceConsistency` reports a future inventory-tag mismatch and does not change speed. Types live in `BoatProfile.swift` and `SimulationState.swift` rather than new Model files.

## Clocks that stay

Physics 20 Hz. Environment and sensor redraw 1 s. NMEA per sentence. UI 10 Hz. Speed integration uses the tick `deltaTime` already computed from successive simulation timestamps.

## Models

`PolarModel` is the only interpolation entry. `BoatProfile` keeps `estimatedBoatSpeed` and `optimalUpwindTrueWindAngleDegrees` as wrappers. The First 40.7 table, bilinear interpolation, and the pinch factor `(TWA / firstTabulatedAngle)^2` move verbatim.

Two slots:

- Reference polar. The future estimator may read this. Default: First 40.7.
- Hidden polar. Generates vessel speed. Default: the same table as the reference, so today's From Wind numbers stay put until an experiment changes the hidden slot.

Hidden polar id, hidden factors, and the integrated speed state live on `SimulationState` only. They are absent from `SimulationInputMirror`, `SimulationSnapshot`, and sentence builders.

The selectable vessels are stored by UUID. Extasy and Nimana are the seeded profiles. A missing selection on a fresh install uses Extasy. A stored reference that cannot be resolved stays unresolved.

## Speed

Instant mode is the default and the current formula, including the live-weather 0.96 factor and the speed-offset penalty.

First-order mode, opt-in:

```text
V_target = V_hidden(TWS, TWA) * hull * sail * trim * seaState * maneuverRetention
V(t+dt) = V_target + (V(t) - V_target) * exp(-dt / tau)
```

`tau` is the acceleration constant when `V < V_target`, otherwise the deceleration constant. `tau <= 0` uses the instant assignment. `dt` is the simulation step. The same filter accepts a manual speed command when that mode is selected. Default Manual mode still assigns the command immediately.

## Maneuvers

The existing heading animator is unchanged. A maneuver is a tack when the shortest turn passes through the true wind, and a gybe when it passes through true wind + 180°. `beginTackManeuver` still targets the opposite close-hauled course. A gybe entry point may call the same animator with a downwind target.

While a maneuver is active and retention is below 1, `V_target` is multiplied by a retention that is 1 at the ends and the configured minimum at mid-turn. Recovery is the same first-order filter catching back up. Instant mode with retention 1 is today's behavior.

## Sails

`SailConfiguration` holds stable string ids for mainsail, headsail, and downwind sail, plus a reef step (`full`, `reef1`, `reef2`, `reef3`). A shared id is a UUID string when it comes from Extasy `ActiveSailConfig` (`mainSailID`, `headsailID`, `kiteID`). Switching configuration does not invent aerodynamic force. It can select a hidden polar or a performance factor only when an experiment says so.

## Parameters

`PerformanceParameters` holds hull, sail, trim, and sea-state factors (default 1), both time constants, both maneuver retentions, and the speed-response mode. A change is a timestamped value appended for the simulation queue. The tick applies it when `timestamp >= change.time` and keeps the current STW. Factors change the vessel target. They do not add a second sensor value. M1 still publishes STW as the measurement.

## Files

Add: `Model/PolarModel.swift`, `Model/PerformanceParameters.swift`, `Model/SailConfiguration.swift`, `MarineSimulatorTests/PolarDynamicsTests.swift`.

Modify: `Model/BoatProfile.swift`, `Model/SimulationState.swift`, `NMEA/SimulationEngine.swift`, `NMEA/NMEASimulator+Tack.swift`.

Do not put hidden fields on `NMEASimulator` or in `SimulationInputMirror`.

## Phases

1. Move interpolation behind `PolarModel` without changing numbers.
2. Add reference and hidden slots. Hidden defaults to the reference.
3. Add instant and first-order speed response.
4. Add tack and gybe retention on the existing animator.
5. Add `SailConfiguration` with no inventory UI.
6. Add the timestamped parameter log.
7. Run the new tests and the existing suite.

## Tests

Clock-driven ticks. Instant mode matches today's From Wind speed. First-order approaches a step target from below and from above, and two equal `dt` steps match one `2 dt` step within the exponential formula. Tack retention lowers STW and recovery follows `tau`. Gybe classification does not change tack heading. A parameter change at time T leaves STW continuous and changes the target only at T. Encoding the input mirror does not contain hidden factor names. Sail id switches without changing NMEA until a factor is set. Manual mode and GPS distance tests stay on instant mode.

## Effort

About 7–9 days for one engineer. Phase 1 is the risky mechanical move. Later phases are additive and default off.
