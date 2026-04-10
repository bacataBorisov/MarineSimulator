# Cache (context)

**You edit this file.** Keep it short (objective, next step, constraints, risks). After **begin-chat** / **`scanned-summary.md`**, **fill the bullets below** for this session (even if the task is “waiting for user” — say so). An empty cache is misleading for the next agent.

**Auto context:** read **`scanned-summary.md`** in this folder first — it is filled from the scan + README (see **`begin-chat.md`**). Repo-root path: **`.agent-os/context/scanned-summary.md`**. Then **`../../AGENTS.md`** at repo root if it exists.

The file **`../state/cache.md`** is separate: it is **regenerated** by `agentos cache update` from scan **change** rows only.

- **Objective:** Active session is initialized; no product/code task has been assigned yet.
- **Immediate next step:** Wait for the user's first task, then inspect the relevant Swift/UI files, verify current behavior in code, and implement only the requested change.
- **Critical constraints:** Follow repo-root **`AGENTS.md`** and **`.agent-os/context/`** workflow; do not invent requirements or timelines; keep changes scoped to the request; use **`../state/cache.md`** only for latest scan deltas.
- **Risks:** None yet.
