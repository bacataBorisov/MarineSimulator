# Begin chat

Read these in order at **session start**:

1. **`scanned-summary.md`** — **auto-generated** repo overview (scan stats, top-level tree, README preview, file-type counts). Refreshed by `agentos cache update`.
2. **`../../AGENTS.md`** (repository root) — **if the file exists**, read it next for Cursor / team rules and pointers. The Agent OS CLI **never** edits this file. If it conflicts with **`context/`**, prefer **`cache.md`** here for *this* session’s intent and follow **`AGENTS.md`** for repo-wide policy. **Xcode:** after **`agentos`** (or **`agentos xcode integrate`**), **`AGENTS.md`** is registered in **`project.pbxproj`** when the file exists, so it should appear beside **`AGENT_OS.md`**. If it is missing from the sidebar, open **`../../AGENTS.md`** from the repo root or run **`agentos xcode integrate`** again. If your environment blocks reading it, ask the user to open or paste it.
3. **`cache.md`** (this folder) — **your** rolling objective, constraints, risks (you edit this).
4. **`../state/current-handoff.md`** — scan-backed handoff (refreshed by `agentos handoff update`).
5. **`project-memory.md`** — durable decisions and patterns.
6. **`open-questions.md`** — unresolved unknowns.

**Machine facts:** **`../state/cache.md`** lists **non-unchanged** files in the **latest** scan only — use it for **deltas**, not the full tree.

**Optional:** skim **`../exports/context-pack.md`** if you recently ran `agentos export` (use `--profile deep` for a larger pack).

Then: state objective, next step, constraints, risks; **verify against the codebase** (paths may contain spaces, e.g. `File 2.swift`); short status; continue with the user’s task.

**Rules:** this **`context/`** folder is authoritative over prior chat for workflow. Do not invent requirements or timelines. Prune stale content.
