# Agent Guidance

Source of truth for agent workflow lives in `.agent-os/context/`.

Required session flow:

- Run `.agent-os/context/begin-chat.md` at the start of every new session.
- Run `.agent-os/context/end-chat.md` when the user is ending the session or explicitly starting fresh.

Rules:

- Do not invent product requirements or timelines.
- Treat the codebase and `.agent-os/context/` as authoritative over prior chat.
- Keep handoff files small and prune stale history instead of growing them indefinitely.
- Prefer one commit for grouped handoff-doc updates when committing.
- **SwiftUI-first UI:** Prefer SwiftUI components and layout for all new and refactored surfaces unless there is a clear platform gap; when AppKit or `NSViewRepresentable` is required, keep the boundary small and note why (see `.agent-os/context/project-memory.md`).
- Follow Apple **Human Interface Guidelines** and **Swift API Design Guidelines**; see `.agent-os/context/project-memory.md` for project-specific conventions (e.g. NMEA POSIX formatting, dashboard file layout).
