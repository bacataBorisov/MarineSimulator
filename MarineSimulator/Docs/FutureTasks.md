# Future Tasks

This is the task pool for work that is planned but not currently active.

## Engine

- [ ] Add isolated wind modes so AWA/TWA/TWD/TWS can be driven independently when needed.
- [ ] Add damping/filtering options for instrument behavior.
- [ ] Add simulator mode and read/ingest mode.
- [ ] Design a protocol abstraction layer so one vessel simulation core can feed multiple output protocols cleanly.

## NMEA Fidelity

- [ ] Clean up the sensor and sentence domain model so communication features do not live inside sensor-state toggles.
- [ ] Plan future NMEA 2000 support as a separate PGN/CAN-oriented output path, not as an extension of the current NMEA 0183 sentence builder.
- [ ] Add AIS output support with `AIVDM` / `AIVDO`, including multi-fragment handling and a high-speed `38400` baud profile equivalent for serial-style output.
- [ ] Add DSC / DSE simulation for VHF distress and target-calling workflows.
- [ ] Add environmental sentences used on sailboats and integrated plotters, especially `XDR`, `MDA`, and `VDR`.
- [ ] Add steering and autopilot-facing sentences such as `RSA`, `APB`, `RMB`, `XTE`, `BWC`, and `BWR`.
- [ ] Add target / tracking sentences such as `TTM` and `TLL` for MARPA / ARPA-style testing.

## UI And Workflow

- [ ] Add save/load presets in configuration.
- [ ] Add unit switching for speed and other measurements.
- [ ] Refactor dashboard helper code into dedicated files.
- [ ] Add compact collapsed mode for the right-side readout.
- [ ] Add the pseudo boat to compass and wind instruments.
- [ ] Improve light mode so it is less harsh.

## Product

- [ ] Set up the local development environment so Codex can manage git operations directly if the host runtime allows it.
- [ ] Create a demo video once the simulator is technically trustworthy.
- [ ] Prepare a public GitHub-facing README after the next engine milestones.
