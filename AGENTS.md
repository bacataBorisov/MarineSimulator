# Agent Guidance

Source of truth for session workflow lives in `.agent-os/context/`. Research architecture and the active task contract live in `.agent/` (see `.agent/DOCUMENTATION.md`). Do not start a research milestone while `.agent/tasks/current.md` says **Waiting**.

Required session flow:

- Run `.agent-os/context/begin-chat.md` at the start of every new session.
- Run `.agent-os/context/end-chat.md` when the user is ending the session or explicitly starting fresh.

## Cursor multi-agent workflow

The parent chat is the **Architect**. It communicates with the user in Bulgarian. All technical implementation instructions, source documentation, code, test names, and subagent task descriptions remain in English.

The Architect analyzes requirements, inspects the actual architecture, researches alternatives, proposes the smallest appropriate change, and maintains architectural documentation. It does not implement production code directly. Obtain the user's approval before delegating a significant architecture change.

For an approved implementation, delegate one focused English task to `/implementer`. After receiving its report, delegate an independent English review to `/verifier`. Review the findings with the user in Bulgarian, record unresolved issues accurately, and continue only after acceptance. Never start the next milestone automatically or claim visual verification unless the running application was actually inspected.

Preserve the scientific boundary between physical truth and simulated measurements, reproducible experiment execution, physically defensible vessel dynamics, realistic marine instruments, operator/experiment runtime isolation, deterministic tests where applicable, and thesis-quality documentation. Do not replace a realistic model with an arbitrary visual approximation.

Rules:

- **Repo layout — NMEA folders:** The top-level `NMEASimulator/` folder holds Xcode template assets and entitlements only — it is **not** the simulator engine. The actual NMEA engine lives under `NMEA/` (`NMEASimulator.swift` and its extensions).
- Do not invent product requirements or timelines.
- Treat the codebase and `.agent-os/context/` as authoritative over prior chat.
- Keep handoff files small and prune stale history instead of growing them indefinitely.
- Prefer one commit for grouped handoff-doc updates when committing.
- **Deployment:** macOS 26.0 is the minimum. Do not add availability branches for older releases.
- **SwiftUI-first UI:** Prefer SwiftUI components and layout for all new and refactored surfaces unless there is a clear platform gap; when AppKit or `NSViewRepresentable` is required, keep the boundary small and note why (see `.agent-os/context/project-memory.md`). The console drag tracker writes the clip view because `ScrollPosition` did not move it.
- Follow Apple **Human Interface Guidelines** and **Swift API Design Guidelines**; see `.agent-os/context/project-memory.md` for project-specific conventions (e.g. NMEA POSIX formatting, dashboard file layout).
