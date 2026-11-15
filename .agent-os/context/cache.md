# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly without subagents or unrequested regression tests unless asked, user smoke-tests). File-split audit Steps 1+2 (removed dead `TopControlBar.swift` & `LeadingSidePanel.swift`; split `ConfigurationChrome.swift` into `ConsoleScrollTracking.swift`, `ConfigurationChrome.swift`, `ConnectionChrome.swift`, `SimulationChrome.swift`) passed focused tests + user smoke test and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Continue file-split audit Step 3 (`Views/MainView.swift`) or fix per-page scroll-position restoration in `Views/ConsoleScrollTracking.swift`.
2. Add atmospheric NMEA output (`MDA` / `XDR` / `MTA` / `MMB` — confirm receiver format first) once the scroll/file-split cleanup settles.
3. Return to GPS `retainedMapResource`.
