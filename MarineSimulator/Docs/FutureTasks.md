# Future Tasks

This is the task pool for work that is planned but not currently active.

## Engine

- [ ] Implement TCP transport in the output layer.
- [ ] Add UI for multiple output endpoints.
- [ ] Persist endpoints, simulator settings, and layout state with `UserDefaults`.
- [ ] Add per-sentence transmission rate controls in the UI.
- [ ] Add fault injection for invalid, missing, delayed, or corrupted sentences.
- [ ] Add drift/current simulation for vessel movement.
- [ ] Add isolated wind modes so AWA/TWA/TWD/TWS can be driven independently when needed.
- [ ] Add damping/filtering options for instrument behavior.
- [ ] Add simulator mode and read/ingest mode.

## NMEA Fidelity

- [ ] Tighten GPS sentence fidelity and keep all GPS sentences internally consistent.
- [ ] Improve heading and variation handling across HDG, HDT, VTG, and VHW.
- [ ] Improve VBW and VLW realism.
- [ ] Add validation coverage for sentence formatting and checksum generation.

## UI And Workflow

- [ ] Add save/load presets in configuration.
- [ ] Add unit switching for speed and other measurements.
- [ ] Refactor dashboard helper code into dedicated files.
- [ ] Add compact collapsed mode for the right-side readout.
- [ ] Add the pseudo boat to compass and wind instruments.
- [ ] Improve light mode so it is less harsh.

## Product

- [ ] Create a demo video once the simulator is technically trustworthy.
- [ ] Prepare a public GitHub-facing README after the next engine milestones.
