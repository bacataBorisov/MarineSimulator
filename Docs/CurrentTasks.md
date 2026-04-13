# Current Tasks

These are the tasks currently in progress or next in line for the active work stream.

Agent handoff reference:

- Scan-backed agent handoff lives in `.agent-os/state/current-handoff.md` (refresh with `agentos handoff update`).
- Use this file (`Docs/CurrentTasks.md`) for product/project task tracking and `.agent-os/context/` for editable session workflow and memory.

## Active

- [ ] Raise NMEA 0183 sentence fidelity further, especially receiver-edge cases and calibration controls.
- [ ] Expand the new in-app manual with deeper sentence-by-sentence behavior notes, network recipes, and troubleshooting guides.
- [ ] Keep the default setup experience minimal while only exposing advanced simulation controls on demand.
- [ ] Expand engine test coverage further into transport-layer churn, movement consistency cases, and additional protocol-invalidity scenarios.
- [ ] Decide whether boat profile and speed mode should live in the dashboard only or also in the main configuration flow.
- [ ] Make nautical chart overlays selectable and tune their presentation against the dashboard map style.

## Resume From Here

1. Continue raising NMEA 0183 sentence fidelity, especially receiver-edge cases and calibration controls that are still simplified.
2. Expand the in-app manual with deeper sentence-by-sentence behavior notes, network recipes, and troubleshooting guidance.
3. Keep refining the default setup flow so advanced simulation and fault tools stay hidden until explicitly needed.
4. Make nautical chart overlays selectable and tune their presentation against the dashboard map style.
5. Expand engine test coverage further into transport churn, movement consistency, and additional protocol-invalidity scenarios.
6. Re-run focused manual checks after any future protocol or transport changes that could affect interoperability.

## Current Focus

- External-reader manual validation is no longer blocking current work.
- The next product effort is quality expansion: more protocol fidelity, better manual coverage, and stronger automated regression protection.
- Best source of truth for what to improve next: the current engine behavior in code plus any remaining simplifications documented in the manual and task docs.
- Boat-speed estimation uses a real First 40.7 VPP table plus pinching realism; further tuning can stay product-driven.
- The nautical chart overlay is present as a first pass; selectability and styling remain open.

## Engineering Notes

- The engine now produces one coherent simulation snapshot per cycle.
- Sentence scheduling now happens per sentence type instead of by coarse bundles.
- UDP output is now modeled as endpoints and can grow into multi-destination output.
- Endpoint configuration and simulator settings now persist through `UserDefaults`.
- Per-sentence transmission rates are now configurable in the sentence setup views.
- Main view selection, console height, and dashboard panel visibility now persist across launches.
- Dashboard map controls now use native-style AppKit MapKit controls with a seamark overlay above the base map.
- TCP transport is now implemented at the endpoint layer.
- Transport status is now surfaced in the toolbar, endpoint editor, and console panel.
- UI sentence enablement is now aligned with engine-side scheduling for wind and hydro sentence dependencies.
- GPS support sentences now derive from snapshot-based fix metadata and a simulated satellite set instead of fixed placeholders.
- Water-track and ground-track behavior are now separated, so hydro and GPS sentences can diverge in a more believable way under simulated current.
- Transport diagnostics now include an in-app event history instead of only the latest endpoint state.
- TCP transport now reports connection lifecycle more clearly and backs off briefly after repeated failures.
- Fault injection now supports dropped, delayed, checksum-corrupted, and invalid-data sentence output with visible event history.
- The app now includes a searchable in-app manual section for terminology, setup, transport, and troubleshooting.
- Configuration now follows a basic-first flow, with advanced transport and fault tools intended to stay hidden until explicitly requested.
- A first live weather mode now uses the boat's GPS coordinates to pull wind and sea-surface temperature from Open-Meteo, with manual mode still available as the default fallback.
- Live weather now uses MET Norway as the primary atmospheric source, with Open-Meteo retained for marine sea temperature only.
- Environmental live-weather values now include gusts, air temperature, humidity, and barometric pressure.
- Boat speed can now be estimated from wind using selectable boat profiles; the First 40.7 profile uses Farr VPP polars with pinching below the minimum tabulated true wind angle.
- Live weather applies mean-reverting wind variation (not independent per-tick jitter), prefers simulated TWD/TWS in the dashboard snapshot, and defaults to a five-minute refresh with one-minute scheduling steps.
- Dashboard relative wind angles use the same heading basis as the map heading indicator; NMEA output still uses true heading for standard true-wind sentences.
- Heading and TWD setpoints wrap through north (359° + 1° → 0°).
- The unit-test suite now verifies every currently emitted 0183 sentence family, wind math consistency, persistence compatibility, one-shot transmission behavior, timer/lifecycle edge cases, live endpoint churn cases, sentence interval suppression, sensor dependency gating, fault mutation paths, delayed release behavior, and selected endpoint normalization rules.
