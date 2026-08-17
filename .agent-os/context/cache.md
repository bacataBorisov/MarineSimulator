# Session Cache

Last updated: 2026-08-16

## Current Objective

**Start here:** only one production file needs a split — `NMEA/NMEASimulator.swift` (2,065 lines). First move: off-main transmit loop (~lines 1534–1952) into `NMEASimulator+TransmitLoop.swift`. Do not merge the main-thread and `simulationQueue` copies of `tickSimulation` in the same change. Audit canvas: refactor-audit.

Optional cleanup (anytime): empty `CompassLabelView 2.swift`, unused `NMEASimulator/Item.swift`, unused `Utilities/WorkPlaygroundStuff.swift`.

## Constraints

Keep NMEA wire output at 20 Hz. Do not invent product features. Do not extract stored properties off `NMEASimulator` — views bind to it directly.

## Risks

Do not put UI publish back on a `Timer` for `.common`. Do not put `NSHostingView` inside `MKAnnotationView`. Do not put ⌘R on both the toolbar and a CommandMenu.

## Overnight soak (morning)

PID 6805, t≈48959s (~13.6 h). App stayed responsive. CPU 17%, 364 MB, energy Low. Beats still apply/consoleSync/display/mapUpdate ≈7–8. No STALL. Old 1 h walk to ~87% CPU did not repeat.

Wake jank: first heading change lagged until a page swap remounted docks. Cause: WindCompass `animationDelta` unbounded + 1 s ease. Snap-on-active + fold delta added.

## Next

TransmitLoop extract is in progress (`NMEASimulator+TransmitLoop.swift`). Next optional splits: LiveWeather, Tack, Endpoints. Do not merge the two tickSimulation paths.
