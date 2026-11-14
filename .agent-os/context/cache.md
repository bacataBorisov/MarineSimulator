# Session Cache

Last updated: 2026-11-14

## Current Objective

Workflow reset to direct single-chat execution: explain plan and architectural fit first, wait for approval, implement directly without subagents or unrequested regression tests, and build for user smoke-testing. Toolbar Continuous/Burst badge + warning text + preview sizes passed user smoke test.

## Constraints

Boat Profile stays lazy `retainedSessionView`. Manual stays ephemeral. Connection, Simulation, and Dashboard lifecycles stay unchanged. Do not restyle deferred pages. Do not add subagent handoffs or new regression tests unless explicitly asked. The user is the external verifier for runtime smoke tests.

## Next

1. Inspect and explain why Dashboard live instruments (`TrailingSidePanel` / `WindCompass`) didn't update during transmission (or verify with timer on), then fix if needed.
2. Fix per-page last scroll-position restoration.
3. Return to GPS `retainedMapResource` and deferred Dashboard work.
