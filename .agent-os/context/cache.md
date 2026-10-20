# Session Cache

Last updated: 2026-08-24

## Current Objective

Accept GPS map/field teleports while transmitting without rewinding the 20 Hz integrator. Keep 20 Hz wire / 10 Hz UI.

## Constraints

Do not put UI publish on a `Timer` for `.common`. Do not put `NSHostingView` in `MKAnnotationView`. Do not put ⌘R on both toolbar and a CommandMenu.

## Next

Protocol fidelity / external-reader check, or stop.
