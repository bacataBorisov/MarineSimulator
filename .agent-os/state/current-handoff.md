# Current handoff

_Updated: 2026-08-16_

## Current work

Session closed. Restored after `1bf7f1b`: toolbar Start/Stop + status chip, sticky Live Controls tab (`dashboard.live_control_category`), sentence-page 50/50 + Live Data title alignment. UDP unreachable is silent (still sending).

## Repo state

- Branch: `main`
- Parent: `1bf7f1b`

## Open decisions

See `.agent-os/context/open-questions.md`.

## Risks

- Do not put UI publish on a `Timer` for `.common`.
- Do not put `NSHostingView` inside `MKAnnotationView`.
- Do not put ⌘R on both the toolbar and a CommandMenu.

## Recommended next actions

- **Morning first:** check the overnight soak (left running 16 Aug ~22:52, PID 6805). Departing mark at t≈828s: 23% CPU, 362 MB, energy Low, beats ≈6–8. Then:
- Split `NMEA/NMEASimulator.swift` (2,065 lines). First file: `NMEASimulator+TransmitLoop.swift` (off-main loop, ~1534–1952). Do not merge main vs queue `tickSimulation` in the same change.
- Dead files if touching cleanup: `CompassLabelView 2.swift`, `NMEASimulator/Item.swift`, `Utilities/WorkPlaygroundStuff.swift`.
- Audit: `.cursor` canvas `refactor-audit.canvas.tsx`.
