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

- Rebuild and glance Wind / Compass / Hydro / GPS plus the toolbar.
- Receiver / soak check if transmitting to a sleeping phone.
