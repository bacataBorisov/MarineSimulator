# UI performance audit

Status: **navigation correction accepted by the user on 2026-11-12.** This is the historical performance record; current selective lifecycle classes and next work live in `ui-architecture.md` and `../tasks/current.md`.

Runtime snapshot at 22:25 on 2026-11-11: macOS reported 38% system memory free. `MarineSimulator` used about 188 MB resident memory and 4.2% CPU in one sample. `HangProbe` logged one 1.5-second main-thread silence during app launch and no later threshold breach in the following 100 seconds. This did not show system memory pressure, but the probe could not detect shorter click latency; navigation still needed an Instruments trace at that point.

## Instruments result

An Animation Hitches recording of the Debug app ran for 30.97 seconds while the user switched sidebar destinations. The instrument included potential interaction delays above 33 ms.

- Meaningful navigation intervals contained main-thread unresponsiveness from 124.78 to 273.01 ms, including two microhangs at 250.75 and 273.01 ms.
- Render hitches reached 133.33 to 366.67 ms and were classified as expensive app updates or renders.
- Samples include fresh SwiftUI work for sentence, Manual, Simulation, Dashboard, Connection, Boat, and Diagnostics destinations. Dashboard return also includes MapKit and console work.
- A terminal 4.35-second hang and 2.19-second hitch overlap trace shutdown and target termination; they are not treated as navigation results.
- The recording confirms the perceived delay and does not support memory pressure as its cause. It does not yet distinguish first-visit construction from warmed repeated navigation.

The run ended in `NSGenericException` at 22:28:22: the window exceeded the allowed number of Update Constraints passes while the user repeatedly opened and closed the console on Manual. Crash-window samples contain `ConsolePanelView.toolbar` and `ConsoleEdgeAnchorView.apply`, with no Dashboard or MapKit frame. A zero-size `CAMetalLayer` warning occurred earlier and remains a separate risk; it is not proven to have caused this crash. Terminal trace events that overlap the crash are excluded.

The focused correction makes the console toolbar toggle cancel any drag and publish one immediate, animation-disabled height. The AppKit resize handle starts a drag only after pointer movement. The authoritative second crash report then identified `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`; `ManualView` replaced its `HSplitView` with a fixed 320-point topics column and flexible article.

A final 30-second real-app Animation Hitches run completed during rapid Manual toggling without `NSGenericException`, and the app remained running. Four potential interaction delays measured 33.67–53.95 ms; the largest render hitch was 83.33 ms. The zero-size `CAMetalLayer` warning still occurred and remained part of the navigation review at that point. One layout-recursion warning appeared after the trace and should be watched for recurrence.

The user then completed several varied stress tests without another crash and accepted the correction on 2026-11-12.

## Warmed Connection ↔ Simulation result

A separate 30-second Animation Hitches run repeatedly switched only between already-visited Connection and Simulation. It recorded 54 main-thread brief-unresponsiveness events, so the latency is not limited to first-visit construction.

- The 27 shorter, Connection-side events measured 147.43–180.02 ms, averaging 161.28 ms. Samples repeatedly include `EndpointEditorView`, `DeferredNumericField`, and the shared console.
- The 27 longer, Simulation-side events measured 210.86–244.63 ms, averaging 226.53 ms. Samples repeatedly include `SimulationView`, `PageContainer`, sensor toggle rows, fault-injection controls, and the shared console.
- Thirteen render hitches at or above 33 ms measured 158.33–237.50 ms, averaging 207.37 ms.
- The first hidden-Dashboard P0 removed the full-size map from detail layout but did not remove the dominant warmed cost: rebuilding substantial destination form trees on every selection change.
- Trace: `/tmp/MarineSimulator-warmed-connection-simulation.trace`.

The bounded-retention control run improved but did not meet no-hitch acceptance:

- Brief unresponsiveness fell from 54 to 44 events; average duration fell from 193.90 to 125.65 ms and maximum from 244.63 to 145.20 ms.
- Render-hitch average fell from 207.37 to 116.67 ms, but the count at or above 33 ms increased from 13 to 19.
- Remaining main-thread samples repeatedly include `RetainedDestinationFrame` layout and alignment, `SimulationView`/`PageContainer` body construction, retained-page focus gating, `EndpointEditorView`, and shared shell work.
- The evidence does not identify Apple Glass as the primary cause. The retained implementation itself still propagates selection into the heavy form trees and traverses their hosted controls.
- Trace: `/tmp/MarineSimulator-warmed-retained-navigation.trace`.

## Final stable-host result and acceptance

The production correction retains only Connection and Simulation in stable `NSHostingView` roots. Destination selection does not rebuild `ConnectionView`, `SimulationView`, `EndpointEditorView`, or `PageContainer`; the latest trace contains zero samples from those heavy bodies.

- Stable AppKit hosts keep their SwiftUI roots unchanged. There is no synchronous `layoutSubtreeIfNeeded`; normal-size changes use AppKit layout.
- An inactive host uses `isHidden = !active`, zero size, zero alpha, disabled hit testing and accessibility, responder resignation with observation, and console-edge anchor suspension. Reactivation reverses those gates and resumes the same anchor.
- The shell still owns one console. No recursive per-field mutation or whole-window key-loop ownership was added.
- The final production trace before the diagnostic recorded 20 brief events averaging 103.63 ms (107.87 ms maximum), 44 interaction delays averaging 90.26 ms, one 419.59 ms microhang, and 15 hitches at or above 33 ms averaging 79.44 ms (91.67 ms maximum). It reported no hang risks.
- Remaining samples are predominantly native AppKit layout/default key-view recalculation and SwiftUI graph work.
- A DEBUG A/B skipped inactive-host `isHidden`. Key-view share was unchanged and hitch rate was about 66% worse, so the experiment was rejected and removed. Production hiding remains.

The user accepted the behavior on 2026-11-12 as visually almost imperceptible. Absolute zero hitches at or above 33 ms under Debug Animation Hitches is no longer the acceptance criterion once heavy body rebuilding is absent, runtime correctness checks pass, and perceived behavior is accepted.

Root-cause review rejected disabling `NSWindow` automatic key-view recalculation or manually owning the entire window key loop. Either would trade a small native layout cost for keyboard-navigation and VoiceOver risk.

## What was measured

`xctrace` is available. The host templates include SwiftUI, Time Profiler, and Animation Hitches. There is no template named Hangs in `xctrace list templates`.

This session could not drive the sidebar. Computer Use refuses without Accessibility and Screen Recording. A trace that does not include the click would not measure the reported lag, so none was recorded.

`log show` for the last three minutes returned no `[MarineSim][hang]` lines. The debug watchdog in `HangProbe` (`Utilities/AppConstants.swift`) logs a stall only when the main thread has been silent for more than 1.5 seconds. Absence of those lines is not a latency number.

## Pre-correction navigation path

`MainView` is a `NavigationSplitView`. The sidebar `List` writes `main_view.selection` through `@AppStorage`. The detail column is a `GeometryReader` and a `ZStack`.

`DashboardView` is always the first child of that `ZStack`. When another destination is selected it stays mounted at opacity 0, with hit testing off. `BoatMapView` stays in that tree. `updateNSView` returns before reading `NMEASimulator` when `isActive` is false, so a hidden map does not keep subscribing to `gpsData` on that call. The `MKMapView` is still in the layout tree at the detail column’s size.

The other child exists only when `SidebarItem.placesConsoleInTheShell` is true (every item except `.dashboard`). It is a `VStack`: `setupDetail(for:)` and one `ConsolePanelView`. `setupDetail` is a `switch`. The previous page’s view value is dropped and the next page’s view is created. Nothing caches a page.

`MainView.onAppear` migrates the console height and copies the selection into `SidebarNavigation`. It does not start the simulation. A later click does not call `startSimulation`, `stopSimulation`, or `ExperimentDiagnosticsSession.prepare`.

Leaving Diagnostics calls `pauseIfRunning()`. If the phase is `.running`, that pauses the experiment loop. Opening the page sets `allowsWallClockLoop = true` and does not prepare a run.

## What each switch created before stable hosts

| Switch | Created | Destroyed | Kept |
|---|---|---|---|
| Dashboard to any other page | That page, plus the shell `ConsolePanelView` and its `NSTextView` | Dashboard top bar, docks, wind compass, and the dashboard console | `DashboardView` and its `MKMapView` |
| Any other page back to Dashboard | Top bar, `LeftControlsPanel`, `TrailingSidePanel`, `WindCompass`, and a new console text view | The shell console and the page | The same `MKMapView` |
| Connection, Simulation, Boat, Manual, Diagnostics, or a sentence page to another of those | The new page only | The previous page | The shell console’s view slot, and the hidden dashboard |
| First visit to Diagnostics after launch | The page, and, on the first `readout`, a second `NMEASimulator` used only to format sentences | — | `ExperimentDiagnosticsSession` on `MainView` |
| Repeat visit to Diagnostics | The page again | The previous page | The session, including the sentence formatter |
| Any visit to GPS | `GPSConfig` and a new `MKMapView` inside `MapWithRightClick` | The previous GPS map | The dashboard map, separately |
| Repeat visit to Boat Profile | A new `VesselLibrarySession` and the form | The previous editor state | `NMEASimulator.vessels`, already loaded |

The shell console occupies a stable second slot in the `VStack` while the selection stays off the dashboard. SwiftUI can keep that `NSView`. This audit did not log `makeNSView`, so reuse is structural, not counted.

`DashboardView` says the same thing in a comment: a sidebar swap remounts the docks and the console, and the map stays.

## Observation

`NMEASimulator`, `SidebarNavigation`, `ExperimentDiagnosticsSession`, and `VesselLibrarySession` are `@Observable`. There is no `ObservableObject` on this path.

`MainView.body` passes the simulator into the environment and into pages. It does not read simulation fields, so a 10 Hz publish does not by itself invalidate `MainView`.

`MainWindowToolbar` reads `isTransmitting`, `latestTransportStatus`, and `outputEndpoints` through `PrimaryOutputSummary`. Those reads refresh the toolbar when those fields change. They do not read `gpsData` or the instrument values.

While transmitting, `applyRuntimeToMain` runs on the main queue at `displayPublishInterval` (0.1 s). It writes a `SimulatedValue` only when `value` changed. It always assigns `lastEmissionDates`, `pendingTransmissions`, the log distances, and the live-weather offsets, then calls `syncInputMirror()`. A view refreshes only if its body read a field that changed. Sentence previews read `twd`, `tws`, `heading`, `speed`, `depth`, and `seaTemp` while `isTransmitting` is true, so those pages recompute during a run. The hidden dashboard does not build the docks, so it does not read those fields while another page is selected.

`ConsoleView` reads `consoleDisplayGeneration` only when the log height is above 1 point. Each change calls `updateNSView`, which coalesces `scheduleSync` to 0.25 s and then appends attributed lines, capped at 200. A new text view has no last record id, so the first sync rebuilds the visible log.

`WindCompass` exists only inside the visible docks. It polls every 0.1 s on `.main` in `.default`, and it also listens for the tack notification. `CompassView` builds `GaugeMarkerCompass.labelSet()` in the view value. Each marker’s `id` is a new `UUID`, so every new `CompassView` value is twelve new `ForEach` identities.

`ExperimentDiagnosticsView.body` reads `session.readout`. That getter calls `currentSentences()`. Before a snapshot exists, that returns six empty rows. After a snapshot exists, it formats MWV, MWD, VHW, HDG, and HDT on the main thread. The first call constructs `NMEASimulator` for a private `UserDefaults` suite, which loads the vessel store and settings. Later calls reuse that instance. The operator simulator is not that instance.

## AppKit lifecycle

| Component | When `makeNSView` runs | Later updates |
|---|---|---|
| Dashboard `MKMapView` | Once, when `DashboardView` first appears | `updateNSView` returns immediately while the page is hidden |
| Boat marker | With the annotation view | `cachedImage` draws a bitmap on a cache miss, then reuses it |
| GPS `MKMapView` | Every time `GPSConfig` is created | `setRegion` on creation; later updates move the pin |
| Console `NSTextView` | Every time that console panel enters the tree | Sync is coalesced; a new view rebuilds the log |
| Resize handle | With the console panel | Forwards the drag; it does not format NMEA |
| Sidebar flattener | With `MainView` | `layout()` walks superviews and sets the split view’s `NSVisualEffectView` to black |

`OpenSeaMapView` has no call site. The anemometer and compass are SwiftUI shapes, not `NSView`s. They are created with the dashboard docks.

## Pre-correction main-thread work on the click

Confirmed on the click path, with no duration:

- Layout of the hidden full-size dashboard, including `MKMapView`, plus layout of the new page.
- Construction of the destination. GPS adds a second `MKMapView`. Returning to the dashboard adds the docks, twelve compass labels, and a new console text view.
- The first Diagnostics `readout` that needs sentences can construct a second `NMEASimulator` on the main thread.
- Leaving a running Diagnostics session cancels that loop on the main actor.

Confirmed beside the click, only while the operator simulation is transmitting:

- `applyRuntimeToMain` and `syncInputMirror()` on the main queue at 10 Hz.
- Console text appends about four times a second when the log is expanded.

Not on the click path: vessel-file loading for Boat Profile (the array is already on the simulator), `startSimulation`, and `prepare`.

## Original causes, by evidence

1. **Confirmed structure.** Every non-dashboard page is laid out on top of a full-size hidden dashboard and its `MKMapView`. The page itself is also built from scratch.
2. **Confirmed structure, boundary only.** Crossing to or from the dashboard destroys and creates a console `NSTextView`, and the return builds the docks and a compass whose marker ids change every value.
3. **Confirmed structure, GPS only.** Each GPS visit creates and later destroys its own `MKMapView`.
4. **Confirmed, first Diagnostics format.** The first sentence format builds a second simulator on the main thread. Every later readout with a snapshot formats six sentences in the view body.
5. **Confirmed concurrent work.** A running operator simulation publishes on the main thread at 10 Hz. That work shares the main thread with the click. Its duration is unmeasured.
6. **Suspected.** The sidebar flattener writes AppKit material during `layout()`.
7. **Suspected.** An opacity-0 `MKMapView` still participates in layout. Whether it also composites is not shown by the source.

No item above has a millisecond figure.

## Historical acceptance criteria and current policy

Use Animation Hitches and the SwiftUI template, same window size, same console height, ten repeats after one warm-up click.

- **Historical strict target:** repeated navigation was initially expected to produce no animation hitch. The final accepted criterion distinguishes Debug instrument events from perceived interaction: retained-page heavy body samples must remain absent, runtime correctness must remain intact, and user-visible behavior must remain acceptable.
- **First visit:** GPS may create a map, and Diagnostics may create the sentence formatter. The main thread must not go silent long enough for `HangProbe` to log `STALL` (its existing threshold is 1.5 s). The click must not wait for a simulation tick.
- **Simulation running:** preserve the runtime checks and record the 10 Hz `apply` and `console.sync` counts from `[MarineSim][hang] beat` when diagnosing a regression.
- **Console drag:** the page height follows `liveHeight` on the drag, with no added animation. That is a separate check from navigation.

Do not hide a stall with a transition. `MainView` already sets the detail transaction’s animation to nil.

## Ownership candidates recorded during the audit

| Area | Today | Extra dependency | Later | Fewer updates | Risk |
|---|---|---|---|---|---|
| Hidden dashboard | Full-size child of every detail layout | Map layout on every sidebar click | Keep one `MKMapView` alive outside the visible column’s layout | Detail layout no longer includes the map | MapKit can drop tiles when the view leaves the window |
| Page identity | `switch` builds a new value | GPS map and Boat session die on every leave | Keep the GPS map host, or the Boat session, at `MainView` if a trace shows that visit is the stall | Repeat visits skip `makeNSView` | A retained page can show stale drafts |
| Diagnostics sentences | `readout` formats on every body | Six builds per refresh after a snapshot | Store the lines on the snapshot timestamp | Body refresh stops formatting | A wrong cache key shows an old sentence |
| Compass markers | New `UUID` per view value | Twelve label identities per dashboard refresh | Stable ids from the degree | Dashboard instrument updates stop recreating labels | Low |
| Operator versus experiment | Already separate objects | Leaving Diagnostics pauses a run | Keep that pause unless a review wants a hidden run | None until the pause changes | A hidden run would keep stepping |

Do not split `NMEASimulator` into a new observation system on this evidence. The 10 Hz path already avoids writing an unchanged `SimulatedValue`.

## Corrections and remaining candidates

**P0 — Hidden dashboard layout. Accepted.** `MainView` retains one `DashboardView` and map host but proposes zero size when another page is selected. The historical zero-size `CAMetalLayer` warning did not establish MapKit as the crash cause; the accepted Manual crash correction is separate.

**P0 — Warmed Connection and Simulation were rebuilt. Accepted.** `MainView` retains only those two destination trees after first visit. Each uses one unchanged `NSHostingView` root; activity, layout, focus, accessibility, responder handling, and anchor suspend/resume live outside the heavy form. Hosted tests preserve root, scroll, control, focus-policy, and anchor identity. The final trace contains zero heavy-body samples, and the user accepted the perceived result.

**P0 candidate — GPS still builds a map each time.** Evidence: `setupDetail` switch; `MapWithRightClick.makeNSView`. Files: `Views/MainView.swift`, `Views/GPS/GPSConfig.swift`, `Views/GPS/MapWithRightClick.swift`. Consider only if a later trace shows repeat GPS visits remain slow. Risk: two map views if the dashboard map is also visible. Check: Time Profiler on the second GPS visit.

**P1 — Diagnostics formats sentences in the view getter, and the first call builds a simulator.** Evidence: `readout` and `makeSentenceBuilder()`. Files: `Model/ExperimentDiagnosticsSession.swift`, `Views/ExperimentDiagnosticsView.swift`. Correction: format when the snapshot changes, not when the body reads. Benefit: opening and refreshing Diagnostics does less main-thread work. Risk: stale lines. Check: one prepare, then SwiftUI instrument while the page is idle and while it is running.

**P1 — Compass labels get new identities whenever the view value is new.** Evidence: `GaugeMarkerCompass.id` is `UUID()`, and `CompassView` calls `labelSet()` on the value. Files: `Views/WindCompassView/CompassView/GaugeMarkerCompass.swift`, `Views/WindCompassView/CompassView/CompassView.swift`. Correction: identify a marker by its degree. Benefit: dashboard refreshes update the dial instead of replacing the labels. Risk: low. Check: SwiftUI update count while the dashboard is visible and the simulation is running.

**P2 — A new console text view rebuilds the log, and the sidebar flattener writes material in `layout()`.** Evidence: `ConsoleLogHost.syncRecords` resets when the last id is missing; `SidebarMaterialFlattener.layout`. Files: `Views/ConsoleView.swift`, `Views/MainView.swift`. Correction: wait for a hitch at the dashboard boundary before changing the text view. Move the material write out of `layout()` only if Time Profiler shows that walk. Risk: a console that misses the tail, or a sidebar that flashes material. Check: hang beats around one dashboard to Connection click with an expanded log.

**Later selective lifecycle work.** Boat Profile is now lazy `retainedSessionView`; Manual remains ephemeral because parking its scrolled topics list reproducibly traps in SwiftUI preference/list removal; GPS `retainedMapResource` is metadata only and remains the next lifecycle slice. Do not add a navigation animation. The first Responsive UI Foundation slice is implemented separately and does not change these lifecycle classes.

## Regression check after any later fix

Stopped and running. Console collapsed and expanded. Diagnostics idle, and Diagnostics running. First click and the tenth click, for every sidebar item. The operator simulator and the experiment session stay separate. One console is in the tree. The map is not created again on a repeat dashboard visit.
