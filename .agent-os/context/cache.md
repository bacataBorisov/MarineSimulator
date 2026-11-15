# Session Cache

Last updated: 2026-11-15

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). File-split cleanup (Steps 1–5), per-page scroll restoration, Weather GPS-off glance hint, Boat numeric-field UX, atmospheric NMEA sentences (`MDA` & `XDR`), GPS `retainedMapResource`, and warm Dashboard map retention passed user smoke tests and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged (Dashboard host stays full-size behind `isHidden` off-dashboard so `MKMapView` stays warm). Do not restyle deferred pages unless requested. The user is the external verifier for runtime smoke tests.

## Next

1. Await user direction (deferred: runtime VoiceOver/keyboard checks, shared master-detail, or remaining page polish).
