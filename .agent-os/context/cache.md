# Session Cache

Last updated: 2026-08-24

## Current Objective

24 h soak passed (t≈79 ks, beats 6–8, heading immediate). GPS wall-dt + deferred MapKit writes + 0.12 s instruments are in. Keep 20 Hz wire / 10 Hz UI.

## Constraints

Do not put UI publish on a `Timer` for `.common`. Do not put `NSHostingView` in `MKAnnotationView`. Do not put ⌘R on both toolbar and a CommandMenu.

## Next

Protocol fidelity / external-reader check, or stop.
