# Future Tasks

This is the task pool for work that is planned but not currently active.

## Engine

- [ ] Add isolated wind modes so AWA/TWA/TWD/TWS can be driven independently when needed.
- [ ] Add simulator mode and read/ingest mode.
- [ ] Design a protocol abstraction layer so one vessel simulation core can feed multiple output protocols cleanly.

## NMEA Fidelity

- [ ] Clean up the sensor and sentence domain model so communication features do not live inside sensor-state toggles.
- [ ] Plan future NMEA 2000 support as a separate PGN/CAN-oriented output path, not as an extension of the current NMEA 0183 sentence builder.
- [ ] Add DSC / DSE simulation for VHF distress and target-calling workflows.
- [ ] Add environmental sentences used on sailboats and integrated plotters, especially `XDR`, `MDA`, and `VDR`.
- [ ] Add steering and autopilot-facing sentences such as `RSA`, `APB`, `RMB`, `XTE`, `BWC`, and `BWR`.
- [ ] Add target / tracking sentences such as `TTM` and `TLL` for MARPA / ARPA-style testing.

## UI And Workflow

- [ ] Add save/load presets in configuration.
- [ ] Add unit switching for speed and other measurements.
- [ ] Refactor dashboard helper code into dedicated files.
- [ ] Add compact collapsed mode for the right-side readout.
- [ ] Add the pseudo boat to compass and wind instruments (map boat marker exists; compass/wind dials still use arrows only).
- [ ] Improve light mode so it is less harsh.
- [x] **HIG UI pass (Configuration + Dashboard):** Implemented Aug 2026 — Connection/Simulation split, Dashboard/console polish, keyboard shortcuts, settings export. See [`HIG-UI-Audit.md`](HIG-UI-Audit.md) Phases 1–4.

## Signal K (needed for Extasy v1.1 connection testing)

Extasy will add zero-config discovery (Bonjour + remembered boats) in **v1.1**. MarineSimulator today emits **NMEA 0183 over UDP/TCP only** — no Signal K JSON/WebSocket, no mDNS advertisement. Extasy cannot fully test “Choose Data Source → Signal K” until the sim can mimic a SK server.

**Goal:** One vessel simulation core → multiple **output protocols** (FutureTasks engine item). Add SK without changing existing NMEA paths.

### Proposed phases (simulator repo — design only)

| Phase | Deliverable | Extasy test unlocked |
|-------|-------------|----------------------|
| SK-A | **Bonjour advertiser** — `_signalk-http._tcp` + `_signalk-ws._tcp` pointing at localhost; minimal HTTP `GET /signalk` JSON | Discovery UI lists a source |
| SK-B | **WebSocket stream** — delta messages from same `SimulationSnapshot` / instrument state as NMEA (wind, GPS, depth, heading) | Extasy v2.0 WS client (future) |
| SK-C | **NMEA-out mode** — SK admin-style TCP/UDP sentence stream on 10110 (optional) | Extasy v1.1 “Connect via NMEA” from discovered SK |
| SK-D | **Configuration UI** — output protocol picker: NMEA 0183 (current) \| Signal K \| both; vessel name in TXT record | Manual + discovery parity |

**Constraints:** Do not alter sentence timing math or `SimulationEngine` physics when adding SK — map SK paths from existing published state (same as NMEA sentence builder source). Reuse `TransportManager` pattern or parallel `SignalKTransport` actor.

**Cross-ref:** Extasy `.agent/guides/connection-discovery.md` in the ExtasyCompleteNavigation repo.


## Far future (no active plan)

- **AIS / vessel traffic:** The app does not ship AIS today. There is no dependable free AIS stream suitable for a simulator, and community aggregators typically expect contributing receivers. If a commercial product ever needed traffic on the map or on the wire, that would mean a **licensed** data provider and/or NMEA `AIVDM` / `AIVDO` output (including multi-fragment handling and higher serial rates where relevant)—not ad hoc polling of hobby feeds.

## Product

- [ ] Set up the local development environment so Codex can manage git operations directly if the host runtime allows it.
- [ ] Create a demo video once the simulator is technically trustworthy.
- [ ] Prepare a public GitHub-facing README after the next engine milestones.
