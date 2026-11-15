# Current task

**Status:** Direct single-chat workflow active. Shared single `ConsolePanelView` in `MainView`, `NSGlassEffectView` map re-center button, normalized `WindCompass` start/fold, `SidebarMaterialFlattener` guard, `GaugeMarkerCompass` stable IDs, and `ExperimentDiagnosticsSession` sentence caching passed user smoke tests and are committed. Next: Step 2 page-switching latency optimization.
**Last updated:** 2026-11-15

## Accepted navigation outcome

- Connection and Simulation use stable retained AppKit hosts. Their unchanged `NSHostingView` roots no longer rebuild `ConnectionView`, `SimulationView`, `EndpointEditorView`, or `PageContainer` bodies during navigation.
- The user judged the current behavior visually almost imperceptible. The final production trace recorded 20 brief events averaging 103.63 ms (107.87 ms maximum), 44 interaction delays averaging 90.26 ms, one 419.59 ms microhang, and 15 hitches at or above 33 ms averaging 79.44 ms (91.67 ms maximum), with no hang risks.
- Remaining samples are predominantly native AppKit layout/default key-view recalculation and SwiftUI graph work. Strict zero events at or above 33 ms under Debug Animation Hitches is no longer the acceptance criterion after heavy body reconstruction was removed and perception was accepted.
- A DEBUG A/B that skipped inactive-host `isHidden` did not change key-view share and worsened hitch rate by about 66%. The diagnostic was removed; production hiding remains.
- Do not disable `NSWindow` automatic key-view recalculation or manually own the whole window key loop. Preserve keyboard, VoiceOver, and runtime correctness checks.
- The Manual console-toggle crash correction remains accepted.

Historical traces and measurements remain in `../architecture/ui-performance-audit.md`.

## Selective lifecycle outcome

- Connection and Simulation remain unchanged as lazy `retainedForm` destinations.
- Boat Profile is lazy `retainedSessionView`. After first visit, one destination root and one `VesselLibrarySession` persist. Valid Boat Profile edits autosave. Selection and the latest persisted profile survive navigation. Invalid intermediate text is not persisted.
- Manual remains `ephemeral`. Keep its accepted 320-point `HStack`, native `List`, and original anchors. Parking a scrolled topics list reproducibly traps in SwiftUI `DynamicContainerInfo.tryRemovingItem` with `DynamicPreferenceCombiner`; do not retain it or inject an AppKit anchor without a separately reviewed design.
- Diagnostics, Wind, Hydro, and Compass remain `ephemeral`. Do not add inactive 10 Hz observation for low-cost sentence pages.
- GPS uses `retainedMapResource` (`GPSSelectorMapResource` in `Views/GPS/MapWithRightClick.swift`): `GPSConfig` remains `ephemeral`, while its `MKMapView`, pin, and camera survive sidebar navigation.
- Keep Dashboard's specialized retained-map lifecycle (full-size `DashboardPageHost` kept warm and hidden via AppKit `isHidden` off-dashboard so `MKMapView` never tears down its Metal surface or flashes on revisit), one-console ownership, automatic key-view handling, scroll anchors, keyboard, VoiceOver, and operator/experiment isolation.
- Runtime UI validation of the lifecycle slice remains outstanding; do not claim it complete from hosted tests alone.
- Runtime VoiceOver and full keyboard/focus traversal remain open. Automated tests do not traverse focus.

## Responsive UI Foundation

Implemented, including the semantic-token follow-up. The window minimum stays 960×640 and does not guarantee a 720×600 content area. Width classes classify available page content after the inset: Compact below 720, Regular from 720 until two 440-point cards fit (900), and Wide at 900 and above. There is no fallback content size. Sidebar, toolbar, and console can shrink the page, and pages scroll.

- Boat and sail rows use a 152/14/280–360 grid and stack below 446 points. The 320-point library is unchanged.
- Connection and Simulation use ordinary stacks chosen by content width. Below 900 points the cards are one column. At 900 and above, paired cards sit in a top-aligned horizontal stack and full-width sections stay outside that pair. Page max for those two pages is 1120. Other pages stay at 920.
- The toolbar title is the sidebar destination name. In-content copies of that title are gone. One shell separator sits under the toolbar.
- Dashboard compact panels, the Dashboard top strip, and shared master-detail are not started. Functional live controls, readouts, and heading behavior are corrected.
- Runtime correction: Onboard Sensors is an ordinary card in both stacks. Boat detail reads the highlighted vessel in its own view. Retained pages are not type-erased, so endpoint add and delete appear without navigation. The toolbar's simulator subscription suppresses later updates in the root host, so the dashboard keeps its own host. Live controls read the simulator in `ControlSliderView`. `TimerStatusText` is a direct child of the Transmission card and reads the timer mode in its own body. `SendIntervalText` reads the interval the same way.
- Heading: the Boat field is the command. With a gyro, that command is stored as the magnetic sample the tick steers from, and the large number is the gyro measurement published by the tick. Without a gyro, the field is magnetic heading and the large number is the live compass. The Heading segment reads those measurements and does not steer.
- Runtime acceptance: the user accepted first-visit Simulation sensors, repeated Boat selection, endpoint add and delete, Dashboard live controls and readouts, and the heading command-versus-measurement behavior. Independent verification accepted the semantic consistency fixes. VoiceOver was not run. Full keyboard and focus traversal remain open. A small transient visual glitch remains when resizing across the one-column/two-column threshold; it is deferred as non-blocking and must not be hidden by custom layout or forced invalidation.

## Still outstanding

- Runtime VoiceOver and full keyboard/focus traversal remain open (manual user checks).
- Shared master-detail for Boat Profile and other selection-detail pages stays deferred (do not force master-detail onto single-form pages).
- One non-blocking resize glitch across the one-column/two-column threshold stays deferred.
- Do not start M4 automatically.
