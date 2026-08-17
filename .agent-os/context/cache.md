# Session Cache

Last updated: 2026-08-16

## Current Objective

Setpoints are user-owned; engine only writes generated `value`. Typed fields commit on Return/blur so the generator keeps the old setpoint while editing.

## Constraints

Keep NMEA wire output at 20 Hz. Do not invent product features.

## Risks

Do not put UI publish back on a `Timer` for `.common`. Do not put `NSHostingView` inside `MKAnnotationView`. Watch memory on long soaks.

## Accepted baseline (Debug, transmitting, dashboard)

- Start: ~18% CPU, ~410 MB
- Soak ~22 min (`t=1362s`): ~61% CPU, ~326 MB
- Soak 1+ hour: still running, ~87% CPU, ~358 MB, energy Low
- Beats stay `apply≈7–8 display≈7–8`
- Filter console: `[MarineSim][hang]`
