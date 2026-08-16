# Project memory

Durable facts and patterns only (not ephemeral session chatter). Prune when obsolete.

- MarineSimulator is a macOS SwiftUI app with a `NavigationSplitView` shell and a map-first dashboard as the primary control surface.
- `NMEASimulator` is the central observable engine/state object; views consume it via SwiftUI environment or `@Bindable`.
- The engine produces one coherent `SimulationSnapshot` per tick and builds all emitted NMEA sentences from that snapshot.
- While transmitting, the fast 20 Hz scheduler runs on `simulationQueue` (`DispatchSourceTimer`); `TransmitRuntime` owns tick state off the main thread. Main-thread UI is published at 10 Hz via coalesced `DispatchQueue.main.asyncAfter` (latest-wins) — not a `Timer` on `.common`, which fires mid-layout and can freeze MapKit. The NMEA console is an AppKit `NSTextView` that appends/trims lines — do not rebuild it with SwiftUI `ForEach`, and do not mutate the text storage inside `updateNSView`.
- Output is endpoint-based and supports both UDP and TCP; the first endpoint is kept in sync with the top-level IP/port fields.
- Settings and live simulator values persist through `UserDefaults`, including layout state, selected panel, sentence intervals, endpoints, presets, and live GPS/control values.
- Product direction currently prioritizes external-reader interoperability, manual validation, and protocol fidelity over adding new feature families.
- Configuration follows a basic-first pattern: core setup is always visible, while advanced transport/fault tools are hidden behind an explicit toggle.
- Live weather V1 exists and is provider-backed, not synthetic: it uses Open-Meteo with GPS coordinates and currently overrides true wind and sea-surface temperature only.
- The dashboard map stays full-bleed behind a full-width bottom console; left/right docks sit in the space above the console and shrink as it grows. Console drag uses an AppKit window-space handle (`ConsoleResizeHandle` in `ConsolePanelView`) because SwiftUI `DragGesture` on the moving bar jitters. Show/hide animates a local height; UserDefaults is persist-only.
- Primary output can be renamed and disabled; the engine no longer forces `outputEndpoints[0].isEnabled = true`.
- The project already has broad engine coverage using the Swift `Testing` framework, including sentence families, persistence, timer/lifecycle, endpoint churn, and fault injection behavior.
- Accepted Debug soak baseline after the freeze fix (dashboard, transmitting): ~26% CPU, ~438 MB, energy Low. Filter `[MarineSim][hang]`. `CAMetalLayer` 0×0 at launch is known noise.
- Do not put SwiftUI `NSHostingView` inside `MKAnnotationView` — it re-enters MapKit layout and wedges the main thread (100% CPU, HangProbe `STALL`). Boat marker is AppKit `NSImageView` rotation only.

## Engineering conventions (Apple-aligned)

- Prefer **Human Interface Guidelines** and **Swift API Design Guidelines**: clear naming, focused types, layouts and controls that behave like system apps.
- **SwiftUI-first:** Implement and evolve the app **visually and structurally in SwiftUI** by default—`View` composition, standard SwiftUI controls (`Slider`, `Picker`, `Button`, materials, stacks), accessibility labels, and platform-appropriate spacing. **Do not** reach for AppKit or `NSViewRepresentable` unless something is **not reasonably achievable** in SwiftUI on the supported macOS baseline, or a **first-party** kit clearly owns the experience (e.g. `MapKit` / `MKMapView`, `MKCompassButton`, `MKZoomControl` on the dashboard map). If an exception is needed, keep the bridge **minimal**, **localized**, and **documented** (comment or PR description).
- Use **`Locale(identifier: "en_US_POSIX")`** (via `NMEANumericFormatting`) for **NMEA numeric fields** so decimal separators stay `.` on all user locales—critical for external receivers.
- **Dashboard rail UI** (`AppChrome`, `RailSection`, `ControlSliderView`, `LiveControlsTabPage`, `LiveControlRailBlock`, etc.) lives in `Views/Dashboard/DashboardChrome.swift`; **`ViewKit`** keeps shared configuration helpers (`SentenceRow`, `ToggleRowWithInfo`, `SentenceIntervalControl`, `displayLabel`). GPS sentence groups persist expand/collapse via `PersistentDisclosureGroup` (`UserDefaults`).
- Sidebar pages share **`PageChrome`** / **`PageContainer`** (24 pt inset, 920 pt max width, Connection as reference). Change those tokens to update Connection, Simulation, Boat, sentence panels, and Manual together. Dashboard stays full-bleed.

### Live Controls rail (leading dock) — layout invariants

Do **not** let the scroll area size itself from **intrinsic width** of the active tab. `Slider` rows and `Picker` rows (e.g. Boat) report different ideal widths; if `ScrollView` content only uses `.frame(maxWidth: .infinity)`, the **document width** can still change when switching segments, so the column **appears to resize horizontally**.

- **`AppChrome.liveControlRailOuterWidth`** must stay in sync with the left rail frame in `DashboardView` (single source: `AppChrome.liveControlRailOuterWidth`).
- **`AppChrome.liveControlScrollViewportWidth`** = outer width minus **only** `railPadding` (the scroll column inside the padded panel).
- **`LiveControlsTabPage`** applies horizontal inset **then** **`.frame(width: liveControlScrollViewportWidth)`** so every tab’s body shares one fixed width.
- **`LiveControlRailBlock`** uses a **leading title column** with `.frame(maxWidth: .infinity, alignment: .leading)` and the value on the right so headline/subtitle don’t “jump” when the trailing string length changes.

New live-controls tabs should go through `LiveControlsTabPage` + `LiveControlRailBlock` (or `ControlSliderView`) rather than custom padding stacks.
