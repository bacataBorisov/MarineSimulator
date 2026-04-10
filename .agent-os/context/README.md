# Context (agent workflow)

This folder lives under **`.agent-os/context/`**. It is the **editable** layer for **how agents start and end work** — separate from the **machine** index (`data/`, `logs/`) and from **scan-derived** notes in **`../state/`**.

- **`scanned-summary.md`** — **auto-filled** on each `agentos cache update` (scan stats, top-level layout, README excerpt). Start here for cold boot.
- Read **`begin-chat.md`** for the full read order (**`AGENTS.md`** at repo root next, if present).
- Use **`end-chat.md`** when wrapping up.
- Keep **`project-memory.md`** and **`open-questions.md`** short and current.

Refresh mechanical facts with:

```bash
agentos-scan scan .
agentos cache update
agentos handoff update
agentos export --profile normal   # or deep
```

The CLI **does not** modify **`AGENTS.md`** at the repo root; add a pointer there yourself if you use Cursor rules.
