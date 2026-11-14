# Agent Guidance

Source of truth for session workflow lives in `.agent-os/context/`. Research architecture and the active task contract live in `.agent/` (see `.agent/DOCUMENTATION.md`). Do not start a research milestone while `.agent/tasks/current.md` says **Waiting**.

Required session flow:

- Run `.agent-os/context/begin-chat.md` at the start of every new session.
- Run `.agent-os/context/end-chat.md` when the user is ending the session or explicitly starting fresh.

## Direct single-chat workflow

The parent chat handles the full workflow directly unless the user explicitly asks to delegate:

1. **Explain first:** Before implementing any requested step, explain in plain English how we plan to do it, why, and how it fits into the current architecture. Wait for user approval.
2. **Implement directly:** Apply the smallest appropriate change in this chat without spawning subagents, `/implementer`, or `/verifier`.
3. **No new regression tests by default:** Do not write or run regression/UI tests unless the user explicitly asks for them. Build cleanly so the app can run.
4. **User smoke-tests and verifies:** The user acts as the external verifier by smoke-testing the running app; proceed only after the user accepts the result.

Communication defaults to English; switch to Bulgarian when writing, translating, or discussing master-thesis text, or when the user requests it. Never start the next milestone automatically or claim visual verification unless the running application was actually inspected.

Preserve the scientific boundary between physical truth and simulated measurements, reproducible experiment execution, physically defensible vessel dynamics, realistic marine instruments, operator/experiment runtime isolation, deterministic tests where applicable, and thesis-quality documentation. Do not replace a realistic model with an arbitrary visual approximation.

Rules:

- **Repo layout — NMEA folders:** The top-level `NMEASimulator/` folder holds Xcode template assets and entitlements only — it is **not** the simulator engine. The actual NMEA engine lives under `NMEA/` (`NMEASimulator.swift` and its extensions).
- Do not invent product requirements or timelines.
- Treat the codebase and `.agent-os/context/` as authoritative over prior chat.
- Keep handoff files small and prune stale history instead of growing them indefinitely.
- Prefer one commit for grouped handoff-doc updates when committing.
- **Agent shell automation:** Keep MarineSimulator temporary artifacts under the ignored workspace `.agent-scratch/`; never use `/tmp`, `/private/tmp`, `/var/tmp`, or another system temp directory. Clean it only with the exact no-argument `/Users/bacataborisov/.local/bin/cursor-clean-marine-scratch` wrapper. Run focused Boat validation with the exact no-argument `/Users/bacataborisov/.local/bin/cursor-test-marine-boat` wrapper. Prefer one allowlisted command per shell call; do not chain, pipe, redirect, use inline interpreters, or broadly allowlist `rm`, shells, or `python3`.
- **Deployment:** macOS 26.0 is the minimum. Do not add availability branches for older releases.
- **Simplicity, responsiveness, and reliability:** For every new or repaired page, prefer direct native SwiftUI composition (`VStack`, `HStack`, `Grid`, standard controls), one observable source of truth, and shared semantic design tokens. Adapt from stacked compact content to multi-column regular/wide content using available container geometry, only when readable content actually fits; preserve semantic reading, keyboard, and accessibility order across reflow. Add a custom `Layout`, view caching/type-erasure layer, forced identity refresh, delayed invalidation, or broader AppKit bridge only after a documented platform limitation. Remove obsolete machinery instead of preserving parallel abstractions. Visual polish follows correct, predictable behavior.
- **SwiftUI-first UI:** Prefer SwiftUI components and layout for all new and refactored surfaces unless there is a clear platform gap; when AppKit or `NSViewRepresentable` is required, keep the boundary small and note why (see `.agent-os/context/project-memory.md`). The console drag tracker writes the clip view because `ScrollPosition` did not move it.
- Follow Apple **Human Interface Guidelines** and **Swift API Design Guidelines**; see `.agent-os/context/project-memory.md` for project-specific conventions (e.g. NMEA POSIX formatting, dashboard file layout).
