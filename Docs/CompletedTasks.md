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
- [x] Add the first engine-focused unit-test suite for checksum generation, sentence building, settings compatibility, persistence round-trip, one-shot send behavior, and drop faults.
- [x] Expand engine tests to cover all currently emitted NMEA 0183 sentence families, wind math consistency, scheduler interval suppression, and core sensor dependency gating.
- [x] Use break-oriented tests to find and fix real engine defects in zero-speed true wind angle handling, primary-endpoint transport normalization, and invalid VHW emission conditions.
- [x] Expand break-oriented tests to cover timer/lifecycle behavior, sentence-specific invalid-data mutations, and latest transport-status consistency after stop.
- [x] Fix engine defects in VTG magnetic variation handling, VBW GPS-unavailable ground fields, first-burst GPS jumps, global timer interval clamping, and latest idle transport-status publication.
- [x] Expand runtime churn tests to cover live secondary-endpoint edits, removals, transport changes, and restart behavior around those changes.
- [x] Move the dashboard map action buttons into a floating toolbar that stays visible above the console drawer and side inspector, and refresh the control styling to fit the newer dashboard chrome.
- [x] Complete the focused manual interoperability pass against the external reader app with the current checklist and confirm the present setup is acceptable for continued feature work.
- [x] Add a first live weather mode that uses the boat's GPS position to fetch wind and sea-surface temperature from Open-Meteo while preserving manual mode as the default fallback.
- [x] Promote MET Norway to the primary live-weather source for atmospheric data, retain Open-Meteo as marine sea-temperature enrichment, and add global fallback behavior.
- [x] Expand live weather to include gusts, air temperature, humidity, and barometric pressure in simulator state and dashboard UI.
- [x] Rework the dashboard top bar into clearer sections and simplify live-weather status presentation.
- [x] Replace the old custom map toolbar with native-style map controls and stabilize the map/control layout.
- [x] Add selectable boat profiles with a first wind-driven boat-speed estimation mode.
- [x] Add a nautical chart seamark overlay to the dashboard map.
- [x] Replace the Beneteau First 40.7 boat-speed polar with the Farr Yacht Design VPP “Best Boatspeeds” grid and scale speed down when true wind angle is inside the polar’s minimum tabulated angle (pinching / no-go behavior).
- [x] Smooth live-weather wind output with mean-reverting noise, align dashboard wind with the same TWD/TWS as the simulated sensors, default live refresh to five minutes, and allow one-minute refresh steps within free-tier–friendly use.
- [x] Align dashboard relative wind (TWA/AWA/AWD/VPW) with the same heading basis as the map heading leg; keep NMEA true-wind math on true heading for external receivers.
- [x] Wrap magnetic heading, gyro heading, and true wind direction setpoints through 0°/360° when nudging or editing setpoints.
- [x] Remove experimental AIS scaffolding; document AIS as far-future only in task docs.
- [x] Add a dedicated bitmap boat marker asset for the dashboard map (replacing ad hoc drawing where applicable).

## Verification

- [x] Source diagnostics checked for the refactored engine files.
- [x] Full project build completed successfully after the refactor.
- [x] Source diagnostics checked for the map-toolbar dashboard update.
- [x] Full project build completed successfully after the map-toolbar dashboard update.
- [x] Full project build and engine test suite completed successfully after live-weather integration.
- [x] Full project build and targeted live-weather tests completed successfully after MET Norway, dashboard, and environmental-data updates.
- [x] Full project build and targeted regression tests completed successfully after boat-profile and nautical-overlay integration.
- [x] Full project build completed successfully after polar realism, live-weather UX, wind-display alignment, heading wrap, and map marker updates.
