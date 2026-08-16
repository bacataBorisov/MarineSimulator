# HIG UI/UX audit — MarineSimulator (macOS)

> **Date:** Aug 15, 2026  
> **Scope:** Audit and proposals only — **no behaviour or math changes** in this pass.  
> **Platform:** macOS 15+ (SwiftUI `NavigationSplitView`, optional macOS 15 console).  
> **References:** [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

---

## Executive summary

MarineSimulator is a capable **pro tool** with a strong Dashboard and useful sentence-level help popovers. The **Configuration** screen carries too much cognitive load: duplicated network fields, long vertical scroll, and mixed “everyday” vs “lab” controls without enough visual hierarchy. macOS HIG favours **clear navigation**, **settings that match mental models**, and **progressive disclosure** — the app is partway there (`Show Advanced`) but the core path still reads like an engineer panel.

**Top 3 wins (no math/transport changes):**

1. Restructure Configuration into **Connection** / **Simulation** / **Advanced** (sidebar subsections or tabbed detail).
2. Fix **accessibility + layout** on Configuration grid rows (labels, alignment, Dynamic Type, VoiceOver).
3. Unify **status + transport** into one connection health strip (toolbar + Configuration), reduce duplicate IP/port display.

---

## Information architecture

### Current

```
Sidebar
├── Dashboard
├── Setup: Configuration | Boat | Manual
└── Sentences: Wind | Compass | Hydro | GPS
Toolbar: Start/Stop | status (transmit, transport, IP, port)
Detail: selected panel + optional Console (non-Dashboard)
```

### HIG alignment

| Area | Assessment | Severity |
|------|------------|----------|
| `NavigationSplitView` + sidebar sections | Good — matches macOS document/split pattern | OK |
| “Sentences” vs “Setup” split | Good — separates wire format from scenario | OK |
| Start/Stop only in toolbar, not Dashboard | Acceptable for pro tool; consider duplicate on Dashboard for discoverability | nice-to-have |
| Console hidden on Dashboard but default elsewhere | Confusing — two console height prefs (`main_view` vs `dashboard`) | should-fix |
| Manual in Setup | OK; could be Help menu item instead | nice-to-have |

**Proposal:** Add sidebar subsection under Setup: **Connection** (network + endpoints only) and **Simulation** (profiles, presets, weather, sensors). Keep full **Configuration** as one scroll page only if users prefer; otherwise split without changing bindings.

---

## Configuration page (`ConfigurationView.swift`)

### Must-fix

| # | Finding | HIG principle | Proposal |
|---|---------|---------------|----------|
| C1 | **Network block duplicates Output Endpoints** — IP/Port/Broadcast at top and again per endpoint | Clarity — one source of truth | Top block = “Quick connect” for primary only; endpoints section owns host/port/broadcast. Or remove top grid and drive primary only from first endpoint card. |
| C2 | **GridRow label/control pairing** — “IP” / TextField / “Port” / TextField on one row without `GridRow` accessibility grouping | Accessibility | Use `LabeledContent` or `Form` rows: “IP address”, “Port”, “Talker ID”. Each control gets explicit label for VoiceOver. |
| C3 | **Broadcast toggle label hidden** (`labelsHidden`) with separate “Broadcast” text in grid | Controls need names | Single `Toggle("Broadcast to subnet", isOn:)` or `LabeledContent("Broadcast", content: Toggle...)`. |
| C4 | **Talker ID** free TextField with no validation hint | Error prevention | Caption: “3 characters, e.g. II or GP”. Disable when hardware profile locks talker. |
| C5 | **Scroll length ~600+ pt** — Hardware, rates, presets, weather, endpoints, transmission, 4× sensor boxes, advanced | Progressive disclosure | Move Weather + Live fetch + Output Endpoints below fold into tabs; default view = Connection + Profile + Start path. |
| C6 | **Sensor boxes in horizontal `HStack`** — wraps badly on narrow windows | Adaptivity | `ViewThatFits` or `LazyVGrid` columns (1 / 2 / 3) by width. |
| C7 | **Typo:** “Humidty” in Environmental Sensors toggle key path | Polish | Fix string when implementing (display copy only). |

### Should-fix

| # | Finding | Proposal |
|---|---------|----------|
| C8 | Test Presets: segmented picker + Apply button — segmented already commits on some platforms; Apply is extra step | Either auto-apply on selection with undo toast, or use menu “Apply preset…” |
| C9 | “Realistic vs Custom” rate mode changes profile silently in `onChange` | Show alert or inline note: “Switched to B&G Triton2 for Realistic intervals” |
| C10 | Live Weather block is dense (grid + 8 lines of provider stats) | Collapse provider details into disclosure group “Last fetch details” |
| C11 | Advanced section duplicates sensor toggles pattern without info buttons | GNSS/DSC rows should use same `ToggleRowWithInfo` as sentence panels |
| C12 | Primary endpoint cannot be disabled but “Enabled” toggle shown disabled | Hide toggle for primary; show “Always on” caption |

### Nice-to-have

| # | Finding | Proposal |
|---|---------|----------|
| C13 | GroupBox everywhere — fine on macOS but heavy | Consider `Form` with `.formStyle(.grouped)` for native settings feel |
| C14 | No empty state when simulation not started and transport idle | Inline banner: “Not sending — press Start in toolbar” |
| C15 | Save/load named configs (already in FutureTasks) | File menu Export/Import JSON settings |

---

## Sentence panels (Wind, GPS, Compass, Hydro)

### Strengths

- `ToggleRowWithInfo` + sentence help popovers — excellent for a simulator; matches HIG **help** pattern.
- Dependency warnings (enable anemometer, etc.) in caption orange — good feedback.
- Interval steppers disabled when Realistic mode — correct progressive disclosure.

### Should-fix

| # | Finding | Proposal |
|---|---------|----------|
| S1 | Wind/GPS/Heading use bare `GeometryReader` + single column — wide window wastes space | Two-column layout: sentences left, live preview / mini compass right (GPS already has map elsewhere) |
| S2 | GPS panel is long scroll with many sentences — no section collapse | `DisclosureGroup` per sentence family (Position / Velocity / Waypoint / GNSS) |
| S3 | Info popovers fixed 300×300 | Size to content; add “Open in Manual” link |
| S4 | Disabled toggles without explaining *which* Configuration toggle to flip | Add button “Open Configuration → Sensors” deep link via sidebar selection |

---

## Dashboard (`DashboardView`, `TopControlBar`)

### Strengths

- Map-centric layout with optional rails — good pro-app pattern (similar to Xcode inspectors).
- Panel toggle icons with `.help()` tooltips.
- Preset icons on toolbar — fast scenario switching.

### Should-fix

| # | Finding | Proposal |
|---|---------|----------|
| D1 | Top bar packs Panels + Scenario + Status + Weather + Updated — overflows on 1280px width | Priority compression: hide “Updated” into weather popover; use `ToolbarItemGroup` with overflow menu |
| D2 | Scenario preset icons lack text labels (icon-only) | `.help()` exists but not enough — add short text under icons at wide width, icons-only at narrow (`ViewThatFits`) |
| D3 | Live Weather toggle icon (`hand.raised` for “back to manual”) is non-obvious | Use `slider.horizontal.3` / `cloud.sun.fill` consistently with Configuration segmented control |
| D4 | Console on Dashboard uses separate `@AppStorage` height from MainView detail console | Single `console_panel.height` key everywhere |
| D5 | Start/Stop only in window toolbar — not visible when Dashboard fills screen on small MacBook | Optional floating transport pill on map (read-only link to same actions) |

### Nice-to-have

| # | Proposal |
|---|----------|
| D6 | Light mode harshness (noted in FutureTasks) — soften map gradient + material opacities for light appearance |
| D7 | Right inspector compact mode (FutureTasks) — HIG **inspector** width ~320–380 pt is OK; allow user-resizable split |

---

## Console (`ConsolePanelView`, `ConsoleView`)

### Strengths

- macOS 15 resize handle + collapse capsule — good touch/pointer affordance.
- Copy (`doc.on.doc`) parity with Extasy terminal workflow — keep.
- Mode segmented control (NMEA vs Transport) — clear.

### Should-fix

| # | Finding | Proposal |
|---|---------|----------|
| O1 | Plain icon buttons (copy/trash) 24×24 — below HIG 28×28 comfort for pointer | Increase hit target; use `.bordered` or toolbar style |
| O2 | Collapse threshold 72 pt is easy to hit accidentally | Slightly higher threshold or “double-click header to collapse” |
| O3 | Console hidden entirely when macOS &lt; 15 in MainView detail | Document minimum OS or provide non-resizable fallback console |

---

## Main window chrome (`MainView`)

### Should-fix

| # | Finding | Proposal |
|---|---------|----------|
| M1 | Status toolbar shows raw IP + port always — duplicates Configuration | Show “Primary: UDP broadcast :4950” human-readable; click opens Configuration |
| M2 | `ensureMinimumWindowWidth` / `resizeMainWindow` defined but unused | Remove dead code or wire to first launch minimum width |
| M3 | Window title “NMEA Simulator” vs product name “MarineSimulator” | Align branding in sidebar title + About panel |
| M4 | No keyboard shortcuts documented | Add ⌘R Start/Stop, ⌘⇧C copy console (standard macOS) — wiring only, same actions |

---

## Accessibility checklist (gap summary)

| Requirement | Status |
|-------------|--------|
| Dynamic Type | Partial — many fixed `.caption` / `.caption2`; test at XL |
| VoiceOver | Grid layouts in Configuration likely read out of order |
| Keyboard navigation | Sentence toggles OK; map/dashboard mostly pointer-only |
| Color-only status | Transport status uses color + icon — OK; add text in toolbar |
| Reduce Motion | Dashboard uses `.snappy` animations — respect `@Environment(\.accessibilityReduceMotion)` |

---

## Visual design / macOS conventions

| Topic | Current | HIG-aligned direction |
|-------|---------|------------------------|
| Materials | Dashboard uses `.regularMaterial` / `.ultraThinMaterial` | Good — keep |
| GroupBox vs Form | Heavy GroupBox stack in Configuration | Prefer `Form` on macOS 14+ for settings |
| Accent | Custom `AppColors` palette | Ensure toggles/buttons use `.tint` for system accent consistency |
| Typography | Mix of system rounded caps labels (Dashboard) and default (Config) | Unify: section headers = `.headline`, helper = `.caption` secondary |

---

## Proposed phased UI work (behaviour unchanged)

### Phase 1 — Configuration clarity (1–2 sessions)

- Refactor network UI to single primary endpoint + “Additional outputs”
- `LabeledContent` / Form rows for IP, port, broadcast, talker
- Sensor grid → adaptive columns
- Connection health banner at top (from `latestTransportStatus`)

### Phase 2 — Navigation polish (1 session)

- Split Configuration or add sidebar items Connection / Simulation
- Unify console height preference
- Toolbar status copy cleanup

### Phase 3 — Dashboard density (1 session)

- TopControlBar overflow menu
- Preset labels at wide size
- Reduce motion support

### Phase 4 — Accessibility pass (1 session) ✅ Done Aug 2026

- VoiceOver walk Configuration + Wind/GPS
- Keyboard shortcuts sheet in Manual

**Status:** Phases 1–4 implemented (UI-only; NMEA math/transport unchanged). Re-verify wire output via checklist row below after major UI edits.

## Out of scope for UI audit (explicit)

- NMEA sentence generation, timing, physics, hardware profiles
- UDP/TCP transport behaviour, broadcast addressing
- Test preset numerical values
- Engine threading / simulation queue

---

## Sign-off

Review this doc before any UI refactor sprint. Pair with [`ManualTestChecklist.md`](ManualTestChecklist.md) after visual changes to confirm wire output unchanged (Copy console vs Extasy `dup≈0` gate).
