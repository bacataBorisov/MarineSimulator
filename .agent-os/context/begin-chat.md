# Begin chat

Read these in order at **session start**:

1. **`cache.md`** (this folder) — **your** rolling objective, constraints, risks (you edit this).
2. **`../state/current-handoff.md`** — scan-backed handoff (refreshed by `agentos handoff update`).
3. **`project-memory.md`** — durable decisions and patterns.
4. **`open-questions.md`** — unresolved unknowns.

**Machine facts:** **`../state/cache.md`** is updated by `agentos cache update` from the latest index — use it for **what changed**, not as a substitute for your intent in **`cache.md`** here.

**Optional:** skim **`../exports/context-pack.md`** if you recently ran `agentos export` (use `--profile deep` for a larger pack).

Then: state objective, next step, constraints, risks; **verify against the codebase**; short status; continue with the user’s task.

**Rules:** this **`context/`** folder is authoritative over prior chat for workflow. Do not invent requirements or timelines. Prune stale content.
