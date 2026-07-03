# Session Cache

Last updated: 2026-07-03

## Current Objective

Fix dead-reckoning regression: boat GPS position must follow the active steering setpoint (gyro when enabled, else magnetic + variation).

## Product State

- Dead reckoning uses `resolvedSteeringTrueHeading`: gyro setpoint drives movement when gyro enabled; magnetic derived for HDG.
- Map bearing uses setpoint fallbacks (`value ?? centerValue`) so slider and marker align before the next sim tick.
- Regression tests: `gpsPositionAdvancesAlongConfiguredHeading*`, `gpsPositionFollowsGyroSetpointNotMagneticCenter`.

## Next

1. NMEA fidelity, manual depth, overlay selectability (see `Docs/CurrentTasks.md`).
2. Optional: broader instrument damping controls (beyond live-wind OU) if needed.

## Notes

- Root cause was b372354 syncing gyro from magnetic each tick, overriding gyro slider and default ~180° magnetic center.
- Run `agentos-scan` / `agentos cache update` / `agentos handoff update` after substantive edits.
