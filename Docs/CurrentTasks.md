# Current Tasks

These are the tasks currently in progress or next in line for the active work stream.

## Active

- [ ] Raise NMEA 0183 sentence fidelity further, especially receiver-edge cases and calibration controls.
- [ ] Expand engine test coverage further into transport-layer churn, movement consistency cases, and additional protocol-invalidity scenarios.
- [ ] Run a focused manual interoperability pass against the external reader app and record any remaining mismatches.
- [ ] Expand the in-app manual with deeper sentence-by-sentence behavior notes, network recipes, and troubleshooting guides now that the dashboard layout is settling down.

## Current Focus

- [ ] Use the improved dashboard, presets, sentence pills, and console tooling to run the next external-reader interoperability pass.
- [ ] Record any remaining wind, heading, GPS, or transport mismatches before changing engine behavior again.
- [ ] Add targeted regression tests for every mismatch found during the manual pass.

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
- Live simulator value edits and preset applications now auto-save so manual testing can resume from the previous setup.
- Named presets now provide quick baseline scenarios for calmer and rougher conditions before interoperability checks.
- Dashboard sensor interlocks now disable live controls when the related onboard instrument is not installed, with gyro heading treated as the preferred source over magnetic heading when both exist.
- The map dashboard now uses overlay side panels, a full-width command bar, instrument-side sentence pills, and a bottom drawer console instead of resizing the map around every panel change.
- The console now supports NMEA versus transport mode switching, collapse/expand drawer behavior, and timestamps on NMEA lines for easier manual verification.
- The unit-test suite now verifies every currently emitted 0183 sentence family, wind math consistency, persistence compatibility, one-shot transmission behavior, timer/lifecycle edge cases, sentence interval suppression, sensor dependency gating, fault mutation paths, delayed release behavior, and selected endpoint normalization rules.
