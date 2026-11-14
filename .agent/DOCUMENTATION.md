# Documentation map

MarineSimulator keeps two agent layers. Do not merge them.

| Layer | Path | Role |
|---|---|---|
| Session workflow | `.agent-os/context/` | `begin-chat.md`, `cache.md`, `project-memory.md`. Still required at session start (`AGENTS.md`). |
| Research hive | `.agent/` | Architecture, audit, roadmap, task contract. Source of truth for thesis work. |

`.agent-os` is not replaced. When they disagree on a durable engineering fact, update `project-memory.md` and this tree together.

## Read path for research work

1. Root `AGENTS.md`
2. This file
3. `.agent/tasks/current.md` — if it says **Waiting**, do not start the next milestone
4. `.agent/ROADMAP.md`
5. `.agent/architecture/` — system map. Prefer it over `investigations/research-readiness-2026-10.md` when they disagree; that audit predates the truth split. The interface map is separate from the physics map: `ui-architecture.md`, `ui-navigation-map.md`, `ui-design-system.md`, `ui-hig-audit.md`, `ui-improvement-plan.md`, and `ui-performance-audit.md`.
6. `.agent-os/context/project-memory.md`
7. The investigation named by the current task

## Roles

The parent chat is the Architect. It owns the roadmap, task slicing, and approval gates. User communication defaults to English; switch to Bulgarian for master-thesis writing/translation or when requested. Technical instructions and source documentation stay in English.

Repository agents live in `.cursor/agents/`:

| Role | Invocation | Does | Does not |
|---|---|---|---|
| Architect | Parent chat | Discuss, plan, delegate, review, and maintain architecture | Implement production code directly |
| Implementer | `/implementer <English task>` | Implement one approved slice, test, build, and report | Unrelated refactors or the next milestone |
| Verifier | `/verifier <English review task>` | Independently review architecture, tests, state, performance, and acceptance criteria | Edit repository files or infer visual correctness from tests |

Both agents return their reports to the parent chat; no prompt transfer to another chat is required. The Architect continues only after the user accepts the reviewed result.

ExtasyCompleteNavigation (`.agent/`, `AGENTS.md`) supplied the pattern: canon in `.agent/`, session state in `.agent-os`, one active task, a report after the task, no automatic next task.
