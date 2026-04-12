# Project memory

Durable facts and patterns only (not ephemeral session chatter). Prune when obsolete.

- MarineSimulator is a macOS SwiftUI app with a `NavigationSplitView` shell and a map-first dashboard as the primary control surface.
- `NMEASimulator` is the central observable engine/state object; views consume it via SwiftUI environment or `@Bindable`.
- The engine produces one coherent `SimulationSnapshot` per tick and builds all emitted NMEA sentences from that snapshot.
- Output is endpoint-based and supports both UDP and TCP; the first endpoint is kept in sync with the top-level IP/port fields.
- Settings and live simulator values persist through `UserDefaults`, including layout state, selected panel, sentence intervals, endpoints, presets, and live GPS/control values.
- Product direction currently prioritizes external-reader interoperability, manual validation, and protocol fidelity over adding new feature families.
- Configuration follows a basic-first pattern: core setup is always visible, while advanced transport/fault tools are hidden behind an explicit toggle.
- Live weather V1 exists and is provider-backed, not synthetic: it uses Open-Meteo with GPS coordinates and currently overrides true wind and sea-surface temperature only.
- The dashboard uses overlay rails plus a bottom console drawer; recent UI work moved map repositioning controls into a floating toolbar to avoid console/inspector overlap.
- The project already has broad engine coverage using the Swift `Testing` framework, including sentence families, persistence, timer/lifecycle, endpoint churn, and fault injection behavior.
