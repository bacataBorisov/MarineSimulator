# Cache (context)

**You edit this file.** Keep it short (objective, next step, constraints, risks). After **begin-chat** / **`scanned-summary.md`**, **fill the bullets below** for this session (even if the task is “waiting for user” — say so). An empty cache is misleading for the next agent.

**Auto context:** read **`scanned-summary.md`** in this folder first — it is filled from the scan + README (see **`begin-chat.md`**). Repo-root path: **`.agent-os/context/scanned-summary.md`**. Then **`../../AGENTS.md`** at repo root if it exists.

The file **`../state/cache.md`** is separate: it is **regenerated** by `agentos cache update` from scan **change** rows only.

- **Objective:** Agent OS test run completed; repo index and exports are fresh — no product task in flight.
- **Immediate next step:** Waiting for user task; on pickup, re-read **`scanned-summary.md`**, **`AGENTS.md`**, and **`begin-chat.md`**, then verify paths in the codebase (including Swift files with spaces in the name).
- **Critical constraints:** Follow **`AGENTS.md`** and **`.agent-os/context/`** for workflow; do not invent requirements or timelines; treat **`../state/cache.md`** as scan deltas only.
- **Risks:** **`init`** resets templates — restore any committed custom **`context/*.md`** from git if needed.
