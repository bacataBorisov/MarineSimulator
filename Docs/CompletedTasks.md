# Completed Tasks

This file tracks finished work that should not remain in the active queue.

## Completed

- [x] Convert project notes into a structured project overview document.
- [x] Introduce a coherent simulation tick that produces one snapshot per cycle.
- [x] Separate simulation state from sentence formatting.
- [x] Replace coarse grouped transmission with sentence-level scheduling foundations.
- [x] Add engine-side support for explicit output endpoints.
- [x] Rework UDP sending so connections are reusable per endpoint.
- [x] Keep the current app building after the engine foundation refactor.
- [x] Add configuration UI support for multiple output endpoints.
- [x] Persist last-used simulator settings and endpoint configuration with `UserDefaults`.
- [x] Expose the new engine foundation through the current configuration UI.
- [x] Verify the endpoint and persistence flow with a successful project build.
- [x] Reduce repeated UDP connection-refused log spam to one clear warning per endpoint.
- [x] Fix the boat map latitude bug caused by `.magnitude`.
- [x] Add per-sentence transmission rate controls to the sentence setup views.
- [x] Persist per-sentence transmission rates with the rest of simulator settings.
- [x] Verify the sentence-rate UI build after integration.
- [x] Persist main view selection, console height, and dashboard panel visibility.
- [x] Verify UI layout state persistence changes with a successful project build.
- [x] Implement TCP transport behind the existing endpoint model.
- [x] Surface transport diagnostics in the app UI instead of only in the Xcode console.
- [x] Verify TCP/diagnostics integration with a successful project build.
- [x] Align wind and hydro sentence enablement rules between the UI and the engine scheduler.
- [x] Allow valid zero-offset DPT output while still rejecting unrealistic offsets outside the supported range.
- [x] Replace fixed GPS support placeholders with snapshot-based GGA/GSA/GSV data.
- [x] Make magnetic variation consistent across GPS and heading-related sentences within the same simulation tick.
- [x] Separate simulated water motion from GPS ground track using a deterministic current model.
- [x] Improve VHW, VBW, VLW, and turn-rate coherence so hydro and heading sentences use the same movement assumptions.
- [x] Add an in-app transport diagnostics/history surface for endpoint events and simulator lifecycle transitions.
- [x] Harden TCP connection lifecycle reporting and retry cooldown behavior under repeated failures.
- [x] Add a repo-based instruction manual scaffold for operator and troubleshooting notes.
- [x] Add a first fault-injection system for dropped, delayed, checksum-corrupted, and invalid-data sentences.
- [x] Add a searchable in-app manual section with terminology, workflow, multi-endpoint, and troubleshooting guidance.
- [x] Reorganize the configuration screen into a basic-first setup flow with advanced simulation controls hidden by default.
- [x] Persist last-used live simulator values so test sessions resume from the most recent setup.
- [x] Add named simulation presets for faster manual interoperability setup.
- [x] Add the first engine-focused unit-test suite for checksum generation, sentence building, settings compatibility, persistence round-trip, one-shot send behavior, and drop faults.
- [x] Expand engine tests to cover all currently emitted NMEA 0183 sentence families, wind math consistency, scheduler interval suppression, and core sensor dependency gating.
- [x] Use break-oriented tests to find and fix real engine defects in zero-speed true wind angle handling, primary-endpoint transport normalization, and invalid VHW emission conditions.
- [x] Expand break-oriented tests to cover timer/lifecycle behavior, sentence-specific invalid-data mutations, and latest transport-status consistency after stop.
- [x] Fix engine defects in VTG magnetic variation handling, VBW GPS-unavailable ground fields, first-burst GPS jumps, global timer interval clamping, and latest idle transport-status publication.
- [x] Fix true-versus-magnetic wind/heading consistency so the dashboard wind presentation and emitted wind sentences agree with external readers.
- [x] Enforce dashboard sensor interlocks and heading-source priority so disabled instruments cannot still be driven from live controls.
- [x] Add stronger engine coverage for wind edge cases, checksum validity, persistence helpers, and heading-source precedence.
- [x] Rework the dashboard into a map-first macOS layout with overlay side panels, a full-width command bar, presets, and instrument-side sentence controls.
- [x] Convert the console into a bottom drawer with mode switching, timestamps for NMEA output, and simpler transport/NMEA log presentation.

## Verification

- [x] Source diagnostics checked for the refactored engine files.
- [x] Full project build completed successfully after the refactor.
