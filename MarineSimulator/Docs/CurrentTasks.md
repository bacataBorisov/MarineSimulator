# Current Tasks

These are the tasks currently in progress or next in line for the active work stream.

Agent handoff reference:

- Agent session state and latest technical handoff live in `docs/agent/current-handoff.md`.
- Use this file for product/project task tracking and `docs/agent/` for per-session agent memory.

## Active

- [ ] Raise NMEA 0183 sentence fidelity further, especially receiver-edge cases and calibration controls.
- [ ] Expand the new in-app manual with deeper sentence-by-sentence behavior notes, network recipes, and troubleshooting guides.
- [ ] Keep the default setup experience minimal while only exposing advanced simulation controls on demand.
- [ ] Expand engine test coverage further into transport-layer churn, movement consistency cases, and additional protocol-invalidity scenarios.
- [ ] Run a focused manual interoperability pass against the external reader app and record any remaining mismatches.

## Resume From Here

1. Run `MarineSimulator/Docs/ManualTestChecklist.md` against the external reader app.
2. Record any mismatches by sentence family or transport mode before changing code.
3. Fix real interoperability defects first, especially `MWV`, `MWD`, `HDG`, `HDT`, `VTG`, `RMC`, and UDP/TCP endpoint behavior.
4. After external-reader behavior is stable, add targeted engine tests for each mismatch that was found.
5. Only after that, continue with manual expansion, more edge-case fidelity, and any broader protocol growth.

## Current Focus

- Primary validation target: external-reader interoperability, not new feature expansion.
- Most likely next bugs, if any remain: sentence interpretation mismatches, transport lifecycle issues, and receiver-specific acceptance quirks.
- Best source of truth for what to verify next: `MarineSimulator/Docs/ManualTestChecklist.md` plus the current engine behavior in code.

## Engineering Notes

- The engine now produces one coherent simulation snapshot per cycle.
- Sentence scheduling now happens per sentence type instead of by coarse bundles.
- UDP output is now modeled as endpoints and can grow into multi-destination output.
- Endpoint configuration and simulator settings now persist through `UserDefaults`.
- Per-sentence transmission rates are now configurable in the sentence setup views.
- Main view selection, console height, and dashboard panel visibility now persist across launches.
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
- The unit-test suite now verifies every currently emitted 0183 sentence family, wind math consistency, persistence compatibility, one-shot transmission behavior, timer/lifecycle edge cases, live endpoint churn cases, sentence interval suppression, sensor dependency gating, fault mutation paths, delayed release behavior, and selected endpoint normalization rules.
