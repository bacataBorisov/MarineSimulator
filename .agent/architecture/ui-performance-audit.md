# UI performance audit

Status: **audit followed by a P0 correction and Instruments recordings, 2026-11-12.** Navigation latency remains measurable. The Manual console-toggle crash fix is accepted.

Runtime snapshot at 22:25 on 2026-11-11: macOS reported 38% system memory free. `MarineSimulator` used about 188 MB resident memory and 4.2% CPU in one sample. `HangProbe` logged one 1.5-second main-thread silence during app launch and no later threshold breach in the following 100 seconds. This does not show system memory pressure, but the probe cannot detect shorter click latency; navigation still needs an Instruments trace.

## Instruments result

An Animation Hitches recording of the Debug app ran for 30.97 seconds while the user switched sidebar destinations. The instrument included potential interaction delays above 33 ms.

- Meaningful navigation intervals contained main-thread unresponsiveness from 124.78 to 273.01 ms, including two microhangs at 250.75 and 273.01 ms.
- Render hitches reached 133.33 to 366.67 ms and were classified as expensive app updates or renders.
- Samples include fresh SwiftUI work for sentence, Manual, Simulation, Dashboard, Connection, Boat, and Diagnostics destinations. Dashboard return also includes MapKit and console work.
- A terminal 4.35-second hang and 2.19-second hitch overlap trace shutdown and target termination; they are not treated as navigation results.
- The recording confirms the perceived delay and does not support memory pressure as its cause. It does not yet distinguish first-visit construction from warmed repeated navigation.

The run ended in `NSGenericException` at 22:28:22: the window exceeded the allowed number of Update Constraints passes while the user repeatedly opened and closed the console on Manual. Crash-window samples contain `ConsolePanelView.toolbar` and `ConsoleEdgeAnchorView.apply`, with no Dashboard or MapKit frame. A zero-size `CAMetalLayer` warning occurred earlier and remains a separate risk; it is not proven to have caused this crash. Terminal trace events that overlap the crash are excluded.

The focused correction makes the console toolbar toggle cancel any drag and publish one immediate, animation-disabled height. The AppKit resize handle starts a drag only after pointer movement. The authoritative second crash report then identified `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`; `ManualView` replaced its `HSplitView` with a fixed 320-point topics column and flexible article.

A final 30-second real-app Animation Hitches run completed during rapid Manual toggling without `NSGenericException`, and the app remained running. Four potential interaction delays measured 33.67–53.95 ms; the largest render hitch was 83.33 ms. The zero-size `CAMetalLayer` warning still occurs and remains part of the unaccepted navigation P0. One layout-recursion warning appeared after the trace and should be watched for recurrence.

The user then completed several varied stress tests without another crash and accepted the correction on 2026-11-12.

## What was measured

`xctrace` is available. The host templates include SwiftUI, Time Profiler, and Animation Hitches. There is no template named Hangs in `xctrace list templates`.

This session could not drive the sidebar. Computer Use refuses without Accessibility and Screen Recording. A trace that does not include the click would not measure the reported lag, so none was recorded.

`log show` for the last three minutes returned no `[MarineSim][hang]` lines. The debug watchdog in `HangProbe` (`Utilities/AppConstants.swift`) logs a stall only when the main thread has been silent for more than 1.5 seconds. Absence of those lines is not a latency number.

## Navigation path

`MainView` is a `NavigationSplitView`. The sidebar `List` writes `main_view.selection` through `@AppStorage`. The detail column is a `GeometryReader` and a `ZStack`.

`DashboardView` is always the first child of that `ZStack`. When another destination is selected it stays mounted at opacity 0, with hit testing off. `BoatMapView` stays in that tree. `updateNSView` returns before reading `NMEASimulator` when `isActive` is false, so a hidden map does not keep subscribing to `gpsData` on that call. The `MKMapView` is still in the layout tree at the detail column’s size.

The other child exists only when `SidebarItem.placesConsoleInTheShell` is true (every item except `.dashboard`). It is a `VStack`: `setupDetail(for:)` and one `ConsolePanelView`. `setupDetail` is a `switch`. The previous page’s view value is dropped and the next page’s view is created. Nothing caches a page.

`MainView.onAppear` migrates the console height and copies the selection into `SidebarNavigation`. It does not start the simulation. A later click does not call `startSimulation`, `stopSimulation`, or `ExperimentDiagnosticsSession.prepare`.

Leaving Diagnostics calls `pauseIfRunning()`. If the phase is `.running`, that pauses the experiment loop. Opening the page sets `allowsWallClockLoop = true` and does not prepare a run.

## What each switch creates

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

## Main-thread work on the click

Confirmed on the click path, with no duration:

- Layout of the hidden full-size dashboard, including `MKMapView`, plus layout of the new page.
- Construction of the destination. GPS adds a second `MKMapView`. Returning to the dashboard adds the docks, twelve compass labels, and a new console text view.
- The first Diagnostics `readout` that needs sentences can construct a second `NMEASimulator` on the main thread.
- Leaving a running Diagnostics session cancels that loop on the main actor.

Confirmed beside the click, only while the operator simulation is transmitting:

- `applyRuntimeToMain` and `syncInputMirror()` on the main queue at 10 Hz.
- Console text appends about four times a second when the log is expanded.

Not on the click path: vessel-file loading for Boat Profile (the array is already on the simulator), `startSimulation`, and `prepare`.

## Causes, by evidence

1. **Confirmed structure.** Every non-dashboard page is laid out on top of a full-size hidden dashboard and its `MKMapView`. The page itself is also built from scratch.
2. **Confirmed structure, boundary only.** Crossing to or from the dashboard destroys and creates a console `NSTextView`, and the return builds the docks and a compass whose marker ids change every value.
3. **Confirmed structure, GPS only.** Each GPS visit creates and later destroys its own `MKMapView`.
4. **Confirmed, first Diagnostics format.** The first sentence format builds a second simulator on the main thread. Every later readout with a snapshot formats six sentences in the view body.
5. **Confirmed concurrent work.** A running operator simulation publishes on the main thread at 10 Hz. That work shares the main thread with the click. Its duration is unmeasured.
6. **Suspected.** The sidebar flattener writes AppKit material during `layout()`.
7. **Suspected.** An opacity-0 `MKMapView` still participates in layout. Whether it also composites is not shown by the source.

No item above has a millisecond figure.

## Acceptance criteria

Use Animation Hitches and the SwiftUI template, same window size, same console height, ten repeats after one warm-up click.

- **Repeated navigation, simulation stopped, console either collapsed or expanded:** the sidebar click produces no animation hitch. Compare Dashboard, Connection, Simulation, Boat Profile, Diagnostics, Manual, Wind, Compass, Hydro, and GPS.
- **First visit:** GPS may create a map, and Diagnostics may create the sentence formatter. The main thread must not go silent long enough for `HangProbe` to log `STALL` (its existing threshold is 1.5 s). The click must not wait for a simulation tick.
- **Simulation running:** the same no-hitch bar. Record the 10 Hz `apply` and `console.sync` counts from `[MarineSim][hang] beat` so a hitch can be matched to those scopes.
- **Console drag:** the page height follows `liveHeight` on the drag, with no added animation. That is a separate check from navigation.

Do not hide a stall with a transition. `MainView` already sets the detail transaction’s animation to nil.

## Ownership changes worth making later

| Area | Today | Extra dependency | Later | Fewer updates | Risk |
|---|---|---|---|---|---|
| Hidden dashboard | Full-size child of every detail layout | Map layout on every sidebar click | Keep one `MKMapView` alive outside the visible column’s layout | Detail layout no longer includes the map | MapKit can drop tiles when the view leaves the window |
| Page identity | `switch` builds a new value | GPS map and Boat session die on every leave | Keep the GPS map host, or the Boat session, at `MainView` if a trace shows that visit is the stall | Repeat visits skip `makeNSView` | A retained page can show stale drafts |
| Diagnostics sentences | `readout` formats on every body | Six builds per refresh after a snapshot | Store the lines on the snapshot timestamp | Body refresh stops formatting | A wrong cache key shows an old sentence |
| Compass markers | New `UUID` per view value | Twelve label identities per dashboard refresh | Stable ids from the degree | Dashboard instrument updates stop recreating labels | Low |
| Operator versus experiment | Already separate objects | Leaving Diagnostics pauses a run | Keep that pause unless a review wants a hidden run | None until the pause changes | A hidden run would keep stepping |

Do not split `NMEASimulator` into a new observation system on this evidence. The 10 Hz path already avoids writing an unchanged `SimulatedValue`.

## Smallest later changes

These are not implemented.

**P0 — Hidden dashboard stays in the layout. Implemented, not accepted.** `MainView` retains one `DashboardView` and map host but proposes zero size when another page is selected. Focused tests passed. The run logged a zero-size `CAMetalLayer`, so camera, tile, and layer behavior still need review; the later crash occurred during repeated console toggling and does not establish MapKit as its cause.

**P0 — Pages are rebuilt, and GPS builds a map each time.** Evidence: `setupDetail` switch; `MapWithRightClick.makeNSView`. Files: `Views/MainView.swift`, `Views/GPS/GPSConfig.swift`, `Views/GPS/MapWithRightClick.swift`. Correction: only if the trace shows GPS or Boat is slower on a repeat visit than Connection. Keep that host alive. Benefit: repeat visits skip map creation. Risk: two map views if the dashboard map is also visible. Check: Time Profiler on the second GPS visit.

**P1 — Diagnostics formats sentences in the view getter, and the first call builds a simulator.** Evidence: `readout` and `makeSentenceBuilder()`. Files: `Model/ExperimentDiagnosticsSession.swift`, `Views/ExperimentDiagnosticsView.swift`. Correction: format when the snapshot changes, not when the body reads. Benefit: opening and refreshing Diagnostics does less main-thread work. Risk: stale lines. Check: one prepare, then SwiftUI instrument while the page is idle and while it is running.

**P1 — Compass labels get new identities whenever the view value is new.** Evidence: `GaugeMarkerCompass.id` is `UUID()`, and `CompassView` calls `labelSet()` on the value. Files: `Views/WindCompassView/CompassView/GaugeMarkerCompass.swift`, `Views/WindCompassView/CompassView/CompassView.swift`. Correction: identify a marker by its degree. Benefit: dashboard refreshes update the dial instead of replacing the labels. Risk: low. Check: SwiftUI update count while the dashboard is visible and the simulation is running.

**P2 — A new console text view rebuilds the log, and the sidebar flattener writes material in `layout()`.** Evidence: `ConsoleLogHost.syncRecords` resets when the last id is missing; `SidebarMaterialFlattener.layout`. Files: `Views/ConsoleView.swift`, `Views/MainView.swift`. Correction: wait for a hitch at the dashboard boundary before changing the text view. Move the material write out of `layout()` only if Time Profiler shows that walk. Risk: a console that misses the tail, or a sidebar that flashes material. Check: hang beats around one dashboard to Connection click with an expanded log.

**P3 — None until a hitch remains after the items above.** Do not add a navigation animation.

## Regression check after any later fix

Stopped and running. Console collapsed and expanded. Diagnostics idle, and Diagnostics running. First click and the tenth click, for every sidebar item. The operator simulator and the experiment session stay separate. One console is in the tree. The map is not created again on a repeat dashboard visit.
