# Memory

This directory is **repo-local persistent storage** for Agent OS: long-lived Markdown you add yourself, plus **`session-*.md`** files created when you run **`agentos close-session`**.

The C scanner does not index `.agent-os`, but **`agentos drift check`** reads `*.md` here and validates links against the indexed tree.
