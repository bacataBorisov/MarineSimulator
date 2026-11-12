# Research-readiness audit — 2026-10-21

Inspected source at `0cdd53a`. Tests were not re-run for this audit. Prior GPS physics tests passed in the session that added them; that is not a fresh suite result.

## 1. Architecture

`NMEASimulator` is the observable app state. Transmit copies setpoints into `SimulationState` and runs `SimulationEngine.tickSimulation` at 20 Hz on `simulationQueue`. UI publish is 10 Hz via `asyncAfter`. Sentences come from one `SimulationSnapshot` per tick (`NMEASimulator+SentenceBuilder`, `SentenceScheduler`). UDP/TCP is endpoint-based (`TransportManager`).

There is no separate environment truth, vessel truth, or sensor layer. `SimulatedValue.value` is both the number the boat sails on and the number the sentence prints.

## 2. What already works

- Coherent snapshot per tick; sentence toggles and intervals; UDP and TCP; multi-endpoint.
- GPS integration: `GPSData.updatePosition` (`sog * 0.514444 * dt`), every fast tick, wall `dt`. User lat/lon applies once via `gpsCoordinateSetpointGeneration`.
- `simulatedMovement` adds a current vector. `simulatedCurrent` returns `(0, 0)` — confirmed.
- Bilinear polar interpolation in `PolarTable` (`BoatProfile.swift`). First 40.7 table is labeled Farr Yacht Design VPP, Design #354, racing, rough water, masthead TWS. TWS and TWA are clamped to the table. Below the first tabulated TWA, speed is scaled by `(TWA / minAngle)²`. That pinch factor is a local heuristic, not the VPP.
- The seeded vessels are Extasy and Nimana. A missing selection uses Extasy. A stored reference that cannot be resolved stays unresolved.
- Apparent/true wind helpers exist and are used by MWV/MWD. Heading, gyro, and variation are combined in `resolvedSteeringTrueHeading`.
- Wire faults: drop, delay, bad checksum, invalid fields (`SentenceScheduler.applyFaultInjection`). These mutate sentences, not the boat.
- Manual vs “From Wind” speed (`BoatSpeedMode`).
- About 147 `@Test` functions across 9 files. Strong on sentences, persistence, transport, and the GPS wall-dt regression. Weak on polar boundaries, dynamics, and determinism.

## 3. Findings

### Critical — confirmed

**Sensor noise is the vessel.** `tickSimulation` writes `heading.value`, `speed.value`, and wind values with `generateRandomValue` (uniform in center±offset). `estimatedBoatSpeed` and `resolvedSteeringTrueHeading` then consume those values. A compass offset changes the track. Evidence: `SimulationEngine.swift` weather/heading/speed block, then `simulatedMovement`.

### High — confirmed

**Speed is instantaneous.** `estimatedBoatSpeed` assigns equilibrium polar speed on the sensor-evolution tick. No `tau`, no tack speed loss. Tack code animates heading (`NMEASimulator` tack timer); it does not integrate a speed trajectory.

**No current.** Vector sum exists; the current function is hard-zero. SOG equals STW aside from heading noise.

**No seed.** `Double.random` and live-weather offsets are not reproducible.

**Polar provenance.** Only the First 40.7 comment names a source. No PDF or checksum in this repo. The pinch curve and `seaStatePenalty = 0.96` / `variationPenalty` from `speed.offset` are unexplained constants (`estimatedBoatSpeed`).

### Medium — confirmed gaps

- No sail configuration, leeway, or turn-rate limit. Turn rate is derived after the heading jump (`computedTurnRate`).
- Live-weather wind offsets feed the same `tws`/`twd` used for boat speed, so weather jitter is physics.
- Fault injection cannot express bias, drift, latency, or a failed transducer while the boat keeps sailing.
- Manual mode ignores the polar entirely. Estimated mode requires the speed-log toggle, so “truth speed” disappears when the instrument is off.

### Low

- First-tick `deltaTime` is 0, so the first cycle does not move the boat (tested).
- Gyro is slaved to magnetic heading plus variation when both sensors exist.

### Not defects

- 20 Hz wire / 10 Hz UI split, AppKit console, deferred MapKit camera, GPS map no longer recenters.
- Knot factor `0.514444` matches the regression test. Do not change it.

## 4. Research readiness

Not ready. The simulator can drive a chart plotter. It cannot yet answer “did the estimator see the hidden polar?” because there is no hidden state, no fixed seed, and no export of truth vs measurement.

Mathematical consistency of one tick is better than physical validity. A polar lookup that matches itself is not a validated VPP.

## 5. Reuse without modification

Sentence builders, scheduler intervals, UDP/TCP, endpoint model, `GPSData.updatePosition`, bilinear `PolarTable` structure, First 40.7 numbers as baseline data (with the provenance caveat), existing wire-fault path as Layer D only, display clock, and current regression tests.

## 6. Proposed shape (not started)

- **A Environment:** TWS, TWD, gust state, current vector. Seeded.
- **B Vessel:** position, heading, STW, SOG, COG, speed state, tack, polar id. Integrates A. Ignores sensor noise.
- **C Sensors:** read B/A through bias, drift, delay, dropout.
- **D NMEA:** format C. Existing snapshot builders stay; their inputs become C.

Manual “center ± offset” mode remains the bench UI. Research mode is opt-in.

## 7. Tasks 1–10 and effort

Estimates are one engineer, after M1’s interfaces exist. They are not a schedule commitment.

| Task | Milestone | Estimate |
|---|---|---|
| 1 State split | M1 | 5–8 days |
| 2 Polar abstraction + hidden model | M2 | 4–6 days |
| 3 First-order speed | M2 | 3–5 days |
| 4 Maneuver speed/heading | M2 | 4–6 days |
| 5 Wind scenarios + current | M3 | 4–6 days |
| 6 Sensor error models | M3 | 5–7 days |
| 7 JSON scenarios | M4 | 3–5 days |
| 8 CSV export | M4 | 2–4 days |
| 9 Baseline vs hidden experiments | M4 | 3–4 days |
| 10 Validation tests | each milestone | ~2 days per milestone |

M5 is a writing review, about 3 days, not new physics.

## 8. Sequence

M1 only, after approval. M2 needs the truth types. M3 needs vessel speed to respond to true wind, not to noisy wind. M4 needs seeds from M3. Hidden polar parameters must not be copied into `SimulationInputMirror` or any sentence.

## 9. Risks

- Splitting state can rewind the GPS integrator again if lat/lon is copied from the UI mirror every tick.
- Random heading today is what makes the dashboard “alive.” Replacing it without a sensor layer will look broken.
- The built-in vessels are Extasy and Nimana.
- NMEA 2000 is out of scope (license), and not required for this study.
