# Current Handoff

Project task reference:

- User-facing backlog and project task tracking live in `MarineSimulator/Docs/CurrentTasks.md`.
- Use this file for session state, verification notes, blockers, and next-step handoff.

## What We Did

- Built out a substantial NMEA 0183 simulator foundation with coherent per-tick snapshots.
- Added multi-endpoint output with UDP and TCP transports.
- Added transport diagnostics, event history, and in-app visibility.
- Added persistence for simulator state, endpoints, and several UI state values.
- Added fault injection for dropped, delayed, checksum-corrupted, and invalid-data sentences.
- Added an in-app manual plus repo docs and manual validation checklist.
- Expanded engine tests aggressively, especially around sentence generation, timer behavior, and endpoint churn.
- Added auto-restored live simulator values and named presets for repeatable bench setups.
- Fixed wind/heading consistency issues and mirrored instrument presentation so dashboard wind agrees with emitted NMEA.
- Enforced sensor interlocks in dashboard controls and made gyro heading the preferred derived source when installed.
- Reworked the dashboard into a map-first layout with overlay side rails, a full-width command bar, and instrument-side sentence pills.
- Reworked the console into a bottom drawer with `NMEA` / `Transport` modes, timestamps on NMEA lines, and a collapsible Xcode-style interaction model.

## Verification Status

- Engine test suite is passing.
- Full Xcode test run still shows the placeholder UI tests as not run.
- Recent targeted reruns confirmed the previously canceled trimming/status tests pass.
- Recent runtime-churn coverage includes:
  - disabling and removing secondary endpoints while running
  - changing secondary endpoint host, port, and transport while running
  - restart behavior after secondary-endpoint edits
  - stop-state latest transport-status consistency

## Manual Verification Still Needed

- Run `MarineSimulator/Docs/ManualTestChecklist.md` against the external reader app.
- Compare raw `MWD`, `MWV`, `HDG`, `HDT`, `VTG`, and `RMC` with the receiver UI.
- Validate live UDP/TCP endpoint behavior on real listeners, not just tests.

## Known Gaps

- UI tests are still placeholder-level.
- External-reader compatibility is not fully proven until the checklist is run.
- Advanced movement and turn-rate edge transitions can still be attacked further.
- Some dashboard helper views should still be split into cleaner dedicated files once the layout stops moving.

## Next Steps

1. Run the manual checklist against the external reader.
2. Fix any real interoperability mismatches found there.
3. Add targeted regression tests for every confirmed mismatch.
4. Only then decide whether to add more protocol families or more UI automation.

## Repo Notes

- `Docs/` contains project/user-facing docs.
- `docs/agent/` contains agent memory and operating workflow.
- Use Conventional Commits for future commit messages.
