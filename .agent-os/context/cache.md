# Session Cache

Last updated: 2026-11-14

## Current Objective

Workflow reset to direct single-chat execution: explain plan and architectural fit first, wait for approval, implement directly without subagents or unrequested regression tests, and build for user smoke-testing. Piece 1 (toolbar `@Bindable` child `View`s + idle console generation bump) passed user smoke test.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages. Do not add subagent handoffs or new regression tests unless explicitly asked. The user is the external verifier for runtime smoke tests.

## Next

1. Add clear user-facing indication when Play is pressed with `Enable Timer` disabled (single-shot mode).
2. Fix per-page last scroll-position restoration.
3. Return to GPS `retainedMapResource` and deferred Dashboard work.
