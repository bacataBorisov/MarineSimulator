# UI improvement plan

Status: **macOS 26 is the minimum.** The shell column reserves console space. UI.1e and UI.1f were accepted on 2026-11-11. Native scroll-indicator movement during viewport changes is accepted system behavior. The Manual console-toggle crash correction was accepted on 2026-11-12 after Instruments and varied user stress testing. The first navigation P0 is implemented but not accepted. The NMEA row grid is not started. Charts are out of scope.

## P0 — Console covers the page

**Done in UI.1.** Non-dashboard pages use a `VStack` in `MainView`. The page is the flexible child. `ConsolePanelView` is the bottom child, so its height is layout space. `SentencePage` no longer adds console padding. The dashboard still owns the one console shown on that page, because the map stays full-bleed behind it. `SidebarItem.placesConsoleInTheShell` is false only for `.dashboard`.

A drag updates `liveHeight`, which is the panel’s laid-out log height, so the page shrinks during the drag. The stored height remains the one `ConsoleHeightStorage` value.

UI.1b and UI.1c did not move the page the operator was reading. They adjusted the offset only within 48 points of the document end, and on macOS 15 and later they wrote a `ScrollPosition` from a geometry callback instead of the clip view. UI.1c’s AppKit path did not run on that OS, and its anchor sat outside the scroll view. UI.1d follows the drag from inside the scrolling content: the clip-view offset changes by each viewport-height change, including halfway down a page, and a window or sidebar resize does not. Confirm by dragging the console on Diagnostics halfway down and at the last NMEA row, then on Connection, Simulation, Boat, Manual, and a sentence page, expanding and contracting.

UI.1e stores each shell page’s scroll offset in `PagePresentationSession` on `MainView`. The pages are not left mounted. Manual search and the selected topic use the same session. The user accepted page-local restoration.

UI.1f freezes the anchor’s sidebar item and slot, uses `.id(selected)`, and measures a console drag from the sample where the handle went down. The user accepted the console-drag round trip and page-local behavior. Independent verification still reports a possible delayed-echo race, and one trace showed duplicate Boat Profile anchors; retain these as technical risks if scrolling regresses.

The navigation-latency items below are still not started.

## P2 — NMEA rows do not share a column

**Problem.** In `ExperimentDiagnosticsView.nmeaSection`, each sentence is its own `LabeledContent` inside a `VStack` with 4 points of spacing. There is no `Grid`, no alignment guide, and no fixed label width. `LabeledContent` sizes the label to that row’s string, so “HDT” and “MWV relative” do not share a value edge. The value is a monospaced `Text` and can be selected. A wrapped sentence vertically centers its label because that is the control’s default. Comparison rows and error rows on the same page use two other arrangements: one concatenated string, and an `HStack` with a 140-point title.

**Files.** `Views/ExperimentDiagnosticsView.swift`. Later, the row can live next to `PageChrome` if the inspector adopts it.

**Change.** One `Grid`. Fixed label column, top alignment, monospaced selectable value, wrapping in the value column. Unavailable stays a word. This is the row in `ui-design-system.md`.

**Benefit.** Sentence names and sentences scan as a table.

**Risk.** Low if the grid is local to this section. Do not change sentence generation.

**Check.** Prepare a run with every sentence present, then disable the wind instrument so some rows say Unavailable. Narrow the window until a sentence wraps. Labels stay on one vertical line. Confirm by eye. The session tests do not render the view.

## P1 — Typed diagnostics values commit only on Return

**Problem.** `DiagnosticValueField` calls its commit closure from `onSubmit` only. Prepare and Reset read `ExperimentDiagnosticsSession`, not the uncommitted string.

**Files.** `Views/ExperimentDiagnosticsView.swift`.

**Change.** Commit when the field resigns focus as well as on Return. Keep the rejection message.

**Benefit.** The run uses the number the operator can see.

**Risk.** A half-typed invalid string must not replace the last valid value.

**Check.** Extend `ExperimentDiagnosticsSessionTests` only for the session rule if the commit stays in the view. For the view, type a bias and press Prepare without Return, then look at the measurement. Manual until a UI test exists.

## P1 — Sidebar groups mix jobs

**Problem.** Setup contains Connection, Simulation, Boat, Diagnostics, and Manual. Diagnostics does not write the operator session. Manual does not either.

**Files.** `Views/MainView.swift` (`SidebarItem` and the list). No route type has to change if the sections are only labels.

**Change.** The grouping in `ui-navigation-map.md`. Keep `NavigationSplitView`.

**Benefit.** The experiment is visibly not an operator preference.

**Risk.** `main_view.selection` raw values must stay, or a saved selection of `diagnostics` would fall back to the dashboard.

**Check.** Launch with each saved raw value, including `config`, which already maps to Connection.

## P2 — Visual consistency

**Problem.** Missing numbers are `"--"` in `ViewKit` and the inspector, and Unavailable on Diagnostics. Toggles are switches on sentence pages and checkboxes on Diagnostics. Card padding is 16 in `SettingsCard`, 24 in `PageChrome`, and 12 in the diagnostics banner. The sidebar is forced black.

**Files.** `Utilities/ViewKit.swift`, `Views/Dashboard/SideToolbarRight.swift`, `Views/ExperimentDiagnosticsView.swift`, `Views/SentencePanelLayout.swift`, `Views/MainView.swift`.

**Change.** One missing-value word. One toggle style. One page width. Leave the console gradient alone until contrast is measured. Restoring sidebar material is a separate visual pass, not part of the inset fix.

**Benefit.** Pages look like one macOS app.

**Risk.** Changing `"--"` on the dashboard changes a readout operators already watch. Do that only with a side-by-side look.

**Check.** Light Mode, Dark Mode, and Increase Contrast. Accessibility Inspector on the sidebar and the console text.

## P3 — Later diagnostics, still not a studio

Keep future experiment UI inside the Diagnostics page. Do not add it to the dashboard rails.

| Feature | Place |
|---|---|
| Time-series chart | A section below the current readout, after the rows are reliable. |
| Truth against measurement | The existing comparison sections. A chart reads the same readout. It does not get `hiddenPolarOverride`. |
| Sensor configuration | The existing error section. Still applied on Prepare and Reset. |
| Availability | The existing toggles, still the experiment’s `SensorToggleStates`. |
| Scenario choice | A picker in Experiment Controls when more than one in-memory scenario exists. Not a new sidebar item. |
| NMEA inspection | The existing NMEA section, after the grid fix. |

The normal operator path stays `NMEASimulator`. A chart must not tick the experiment while it redraws.

## Navigation latency — first P0 implemented, not accepted

Source: `ui-performance-audit.md`. Animation Hitches recorded 124.78–273.01 ms main-thread unresponsiveness and 133.33–366.67 ms render hitches while sidebar destinations changed.

**P0, implemented.** `MainView` retains one `DashboardView` and map host but proposes zero size while another page is showing. Focused tests passed. The Instruments run still logs a zero-size `CAMetalLayer`; keep this warning with the unaccepted navigation work.

**Manual crash correction, runtime validated.** The console toggle now cancels drag state and publishes one immediate height, the resize handle arms only after movement, and `ManualView` uses a fixed-column `HStack` instead of `HSplitView`. A final 30-second real-app Animation Hitches run survived rapid toggling with no `NSGenericException`; the largest potential interaction delay was 53.95 ms and the largest render hitch was 83.33 ms. One post-trace layout-recursion warning remains a risk to monitor.

**P1, confirmed and concurrent.** A transmitting run calls `applyRuntimeToMain` on the main queue at 10 Hz. The first Diagnostics readout can construct a second `NMEASimulator` to format sentences. Compass markers use a new `UUID` on every view value.

**P2, suspected.** `SidebarMaterialFlattener.layout` writes the visual-effect material. A new console host rebuilds its log on the first sync.

Next, finish the warmed Connection ↔ Simulation latency measurement before choosing another latency correction. Do not start it automatically or add a transition to hide the work.

## Scroll trace — Debug only, not a fix

The running Debug app records the clip view the anchor holds. Release builds omit the menu, the window, and the records. Capture is off until **Start**. The buffer holds 800 lines and drops the oldest. Nothing is written to disk. The main window does not refresh for a scroll event.

**Open.** **Debug → Scroll Trace…**.

**Start, stop, copy.** **Start** begins a capture. **Stop** ends it. **Clear** drops the lines and leaves capture in its current state. **Copy** puts the build identity, the bound scroll views, and every line on the clipboard. **Refresh** re-reads the buffer. The panel also updates when a record arrives, and those updates are coalesced.

**Build identity, shown at the top of the panel and of every copy.** `configuration=Debug`, `CFBundleShortVersionString` and `CFBundleVersion`, the executable path, that file’s modification time, the process id, and `LSMinimumSystemVersion`. Version and build numbers are unchanged.

**Each line.** Sequence, monotonic uptime, kind, sidebar selection, the anchor’s frozen page, slot, anchor identity, `NSScrollView` identity, `NSClipView` identity, document height, viewport height, clip origin, maximum offset (`max(0, document − viewport)`), distance from the document bottom, stored offset for that frozen page and slot, whether the console handle is down, console height, requested offset, observed offset, and a short note.

**Kinds.** `selection`, `mounted`, `removed`, `anchorCreated`, `anchorBound`, `anchorRetired`, `offsetSaved`, `offsetRestored`, `userScroll`, `dragStarted`, `dragBaseline`, `consoleHeight`, `programmaticWrite`, `boundsAfterWrite`, `clipChanged`, `baselineReplaced`, `lateCallback`, `enclosingMismatch`, `captureStarted`, `captureStopped`.

A programmatic write is `programmaticWrite` with `requested` and `observed` taken from the clip view after `scroll(to:)`. A later sample whose origin is neither the previous origin nor that requested value is `boundsAfterWrite`. `lateCallback` is a sample that arrived after the anchor retired or detached. `enclosingMismatch` means `enclosingScrollView` is no longer the scroll view the anchor bound. Selection is recorded on its own; a line’s frozen page is the anchor’s page, not the sidebar item alone.

**Scenario A.** Start. Open Diagnostics. Scroll it about halfway. Open Simulation. Scroll Simulation somewhere else. Return to Diagnostics. Stop. Copy. Read whether a `diagnostics` `offsetSaved` occurs while `selection=simulation`, whether a `lateCallback` is followed by a write, whether the restore `frozen` page is `diagnostics`, whether `boundsAfterWrite` follows `offsetRestored`, and whether the `scroll=` identity changes between the save and the restore.

**Scenario B.** Clear. Start. Open Diagnostics. Scroll to the bottom and note `doc`, `view`, and `origin`. Drag the console up, then back to the same height. Stop. Copy. Compare the first bottom sample with the last sample: document height, viewport height, origin, whether `boundsAfterWrite` follows the last `programmaticWrite`, whether `scroll=` stays the same, whether `baselineReplaced` appears, and whether more than one `anchor=` writes the same `clip=`.

## Suggested order

1. Shell column and page-local scroll behavior. Done and accepted in UI.1.
2. Diagnostics NMEA grid, and commit numeric fields on focus loss.
3. Sidebar sections.
4. Shared missing value and toggle style.
5. Charts only after those, as their own task.

## Manual inspection still required

UI.1 did not replace this list. Confirm on a built window:

- How many Diagnostics rows the default 220-point console hides.
- Whether Boat and Manual are covered by the same amount.
- Sentence pages at the minimum window width, 960 by 640.
- Sidebar and console contrast in Light Mode and Dark Mode.
- VoiceOver on a diagnostics NMEA row and on a sentence toggle.
- A larger system text size on the diagnostics error row, which is a non-wrapping `HStack`.
