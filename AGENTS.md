# Agent Guidance

Source of truth for agent workflow lives in `docs/agent/`.

Required session flow:

- Run `docs/agent/begin-chat.md` at the start of every new session.
- Run `docs/agent/end-chat.md` when the user is ending the session or explicitly starting fresh.

Rules:

- Do not invent product requirements or timelines.
- Treat the codebase and `docs/agent/` as authoritative over prior chat.
- Keep handoff files small and prune stale history instead of growing them indefinitely.
- Prefer one commit for grouped handoff-doc updates when committing.
