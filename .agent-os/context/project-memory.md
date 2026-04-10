# Project memory

Durable facts and patterns only (not ephemeral session chatter). Prune when obsolete.

- Product and engineering task lists live under repo-root **`Docs/`** (capital **D**). Do not confuse with a lowercase **`docs/`** tree.
- Editable agent workflow (begin/end chat, rolling intent) lives in **`.agent-os/context/`**. Scan-derived notes are in **`.agent-os/state/`**; **`../exports/context-pack.*`** is useful for quick repo orientation.
- Root **`AGENTS.md`** points Cursor and other tools at **`.agent-os/context/`**; the Agent OS CLI does not rewrite it.
