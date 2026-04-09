# Project Memory

- Keep two doc layers separate:
  - `Docs/` for project-facing docs the user reads in Xcode.
  - `docs/agent/` for agent memory and session handoff.
- Prefer a basic-first UI with advanced simulation controls hidden unless clearly needed.
- The simulator should default to unsurprising behavior over invisible realism tricks.
- `MWV` interpretation is a common compatibility trap; explicit guidance belongs in both the in-app manual and troubleshooting docs.
- Primary output endpoint is an invariant and is always re-enabled/synced to the main IP/port fields.
- Favor hostile unit tests that try to break runtime behavior, not just sentence formatting happy paths.
- Current dashboard direction is map-first with overlay side rails and a bottom drawer console; avoid regressing to layouts that resize the map around every panel toggle.
- Commit style should follow Conventional Commits:
  - `feat(scope): ...` for user-visible functionality
  - `fix(scope): ...` for behavior corrections
  - `test(scope): ...` for new or improved test coverage
  - `docs(scope): ...` for documentation-only changes
  - `refactor(scope): ...` for internal restructuring without behavior change
