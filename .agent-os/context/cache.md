# Cache (context)

**You edit this file.** Keep it short (objective, next step, constraints, risks). After **begin-chat** / **`scanned-summary.md`**, **fill the bullets below** for this session (even if the task is “waiting for user” — say so). An empty cache is misleading for the next agent.

**Auto context:** read **`scanned-summary.md`** in this folder first — it is filled from the scan + README (see **`begin-chat.md`**). Repo-root path: **`.agent-os/context/scanned-summary.md`**. Then **`../../AGENTS.md`** at repo root if it exists.

The file **`../state/cache.md`** is separate: it is **regenerated** by `agentos cache update` from scan **change** rows only.

- **Objective:** Use MET Norway as the global primary live-weather source for wind and atmospheric values, with Open-Meteo retained only as a marine enrichment source for sea-surface temperature.
- **Immediate next step:** Manually verify that the app now shows MET Norway wind/gust/air data consistently and only fills sea temperature when Open-Meteo marine responds.
- **Critical constraints:** Follow repo-root **`AGENTS.md`** and **`.agent-os/context/`** workflow; do not invent requirements or timelines; treat `Docs/CurrentTasks.md` as the product queue; keep generated files separate from editable context.
- **Risks:** Sea-surface temperature still depends on Open-Meteo marine and can remain unavailable even when MET Norway succeeds; MET Norway contributes atmospheric fields that are visible in UI but not yet mapped into extra NMEA sentence families, and `BoatMapPreview.swift` still has a preview-only crash report despite clean file diagnostics and successful builds.
