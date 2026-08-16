# Session Cache

Last updated: 2026-08-16

## Current Objective

Hang-monitoring baseline after MapKit marker + 10 Hz display-clock fix. Keep watching for `STALL`.

## Constraints

Keep NMEA wire output at 20 Hz. Do not invent product features.

## Risks

Do not put UI publish back on a `Timer` for `.common`. Do not put `NSHostingView` inside `MKAnnotationView`. Watch memory on long soaks.

## Accepted baseline (Debug, transmitting, dashboard)

- CPU ~26%
- Memory ~438 MB
- Energy Low
- Filter console: `[MarineSim][hang]`
- `CAMetalLayer` 0×0 and `pid 617` port-right messages are known noise
