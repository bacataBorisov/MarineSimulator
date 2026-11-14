# Session Cache

Last updated: 2026-11-14

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly without subagents or unrequested regression tests, user smoke-tests). Right Instruments rail (fixed 280pt, square WindCompass, pure telemetry) and new `Sentences -> Overview` page passed user smoke test and are committed.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages unless requested. Do not add subagent handoffs or new regression tests unless explicitly asked. The user is the external verifier for runtime smoke tests.

## Next

1. Fix per-page last scroll-position restoration.
2. Return to GPS `retainedMapResource` and deferred page polish later.
