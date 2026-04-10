# End chat

When ending the session or starting fresh:

1. Review changes via **diffs / codebase**, not memory alone.
2. Update **`cache.md`** (this folder) in **20 lines or fewer** — your intent and priorities.
3. Optionally fold important narrative into **`project-memory.md`** or **`open-questions.md`**.
4. Prefer **one grouped commit** for handoff updates when you commit.

**Refresh the machine + export layer** so the next session has fresh facts:

```bash
agentos-scan scan .
agentos cache update
agentos handoff update
agentos export --profile normal    # or deep
```

Reply with: what changed, current state, first next step.
