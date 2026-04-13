# Session Cache

Last updated: 2026-04-13

## Current Objective

Ship a coherent simulator update: realistic First 40.7 polar + pinching, calmer live wind, correct wind/heading display vs map, circular heading controls, map boat marker; remove AIS scaffolding.

## Product State

- Live weather: MET Norway + Open-Meteo marine; smoothed wind offsets; 5 min default refresh, 1–60 min UI.
- Dashboard wind uses sensor TWD/TWS and map-aligned heading for relative angles; NMEA keeps true-heading wind math.
- Boat speed from Farr VPP grid with sub–min-TWA pinching factor.

## Next

1. NMEA fidelity, manual depth, overlay selectability (see `Docs/CurrentTasks.md`).
2. Optional: broader instrument damping controls (beyond live-wind OU) if needed.

## Notes

- Prefer `docs/agent/` pointers in `AGENTS.md`; task truth in `Docs/*Tasks.md`.
- Run `agentos-scan` / `agentos cache update` / `agentos handoff update` after substantive edits.
