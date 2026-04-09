# Marine Simulator

## Purpose

Marine Simulator is a macOS app for simulating onboard marine navigation sensors and transmitting NMEA data to external applications over IP networking.

The project exists to provide a better test environment than a simple script-based simulator, especially for validating navigation software such as Extasy Complete Navigation when real boat time is limited.

The current goal is practical:

- Simulate common onboard sensors.
- Transmit believable NMEA output to navigation apps.
- Provide a visual control surface for adjusting values while testing.
- Grow into a more realistic marine test bench over time.

## Product Direction

The app is intended to simulate the boat-side sensor network rather than just emit random strings. The long-term direction is a desktop testing tool that can:

- represent realistic instrument combinations onboard a vessel
- drive multiple consumers over the network
- expose both control and monitoring views
- support presets, repeatable scenarios, and fault injection
- eventually simulate weather and environmental conditions based on vessel location

Top idea for future realism:

- Fetch weather/environment data for the vessel position and derive wind, temperature, water temperature, drift, and related values from it.

## Current Scope

Implemented or partially implemented areas:

- wind simulation
- hydro/depth/speed simulation
- heading simulation
- GPS position simulation
- UDP transmission
- TCP transmission
- multiple output endpoints
- macOS dashboard and configuration UI
- overlay dashboard side panels with a map-centered workflow
- presets and auto-restored last-used simulator state
- NMEA and transport console drawer with timestamps
- sensor and sentence enable/disable controls
- fault injection and transport diagnostics

## Project Management Docs

The project uses a simple task flow documented in the repository:

- `Docs/FutureTasks.md` is the backlog and task pool.
- `Docs/CurrentTasks.md` is the active work queue.
- `Docs/CompletedTasks.md` is the finished work log.

Tasks should move from future to current when selected for work, then into completed once implemented and verified.

## What Is Working

These items are already present in the project and should be treated as the current baseline:

- Start/stop control with mutually exclusive toolbar behavior.
- Adjustable transmission timer.
- Wind input and derived wind calculations.
- GPS module with moving position.
- Magnetic compass support.
- Anemometer support.
- Water temperature support.
- Depth transducer support.
- Speed log support.
- Universal NMEA builder structure in place.
- Sentence/sensor selection UI.
- Min/max-style simulated value control through ranges and offsets.
- Real-time toggle changes while transmitting.
- Sidebar visibility control for map space.
- Console clear action.
- Console drawer collapse/expand behavior with timestamped NMEA output.
- Display of input units.
- Additional NMEA output visibility for confirmation.
- Main window resize behavior around console/layout thresholds.
- Selection of sentence source in some areas.
- Precision improvements for displayed values.
- Dashboard presets for repeatable calm/light/storm setup baselines.
- Dashboard sentence pills for instant sentence enable/disable control.
- Sensor interlocks in live controls, including gyro-over-magnetic heading priority.

## Known Problems

These are the main issues that currently limit the project from being a trustworthy simulator:

- Final sentence fidelity and receiver-compatibility still need more work at the edge-case level.
- GPS, heading, wind, and speed relationships still need more external-reader validation even after recent cleanup.
- Some sentence implementations are incomplete, oversimplified, or placeholder-grade.
- Parts of the dashboard still contain helper code that should be split into cleaner dedicated files.
- The new dashboard layout and console drawer need final UX polish after functional stabilization.
- Manual interoperability evidence against the external reader is still the main missing confidence step.

## Prioritized Roadmap

### Core Simulation

- [ ] Refactor the simulator to produce one coherent state snapshot per tick.
- [ ] Add logic for isolated wind modes such as direct AWA/TWA cases instead of deriving everything from TWD.
- [ ] Add damping or optional filtering for more realistic instrument behavior.
- [ ] Add preset sea/weather modes such as calm, breezy, and storm.
- [ ] Validate sentence correctness more rigorously.
- [ ] Add optional invalid/corrupted sentence simulation for receiver robustness testing.
- [ ] Improve VHW logic:
  - use gyro heading when available
  - otherwise derive true heading from magnetic heading plus variation
- [ ] Add simulator mode and read mode so the app can also ingest live sensor/network data.

### Networking

- [ ] Add TCP/IP output option.
- [ ] Add support for multiple destination IPs/endpoints.
- [ ] Improve the transport layer so it is suitable for persistent and extensible output routing.

### Configuration And Persistence

- [ ] Preserve last used settings with `UserDefaults`.
- [ ] Preserve UI state such as sidebar visibility and layout state.
- [ ] Add save/load presets in the configuration UI.
- [ ] Improve stepper precision behavior.
- [ ] Make currently inactive config controls fully functional.
- [ ] Add unit switching between knots, m/s, km/h, and any additional useful units.

### GPS And Navigation

- [ ] Refactor the GPS module into a cleaner standalone area.
- [ ] Build the missing GPS sentences properly and align the UI with the actual transmission logic.
- [ ] Add drift/current effects so vessel movement is more realistic.

### Dashboard And UI

- [ ] Refactor the dashboard and move helper code into proper files.
- [ ] Add the pseudo boat to the compass and wind instrument.
- [ ] Fix the anemometer view integration to use the simulator state in a cleaner way.
- [ ] Improve the right-side display:
  - when collapsed, shrink to a compact numeric mode instead of disappearing completely
- [ ] Reduce the harshness of light mode.
- [ ] Continue polishing the overall visual finish for public presentation.

### Product And Portfolio

- [ ] Create a private GitHub repository and start tracking progress properly.
- [ ] Create a demo video.
- [ ] Publish the project to GitHub when the baseline is credible.
- [ ] Add the project to the portfolio site once the simulator is technically trustworthy.

## Milestone Log

### 7 June 2025

- Started the basic macOS project.
- Began exploring a 4-part layout.

### 10 June 2025

- Worked on hydro view.
- Added min/max handling for depth and speed.

### 11 June 2025

- Bound views directly to `NMEASimulator` properties.
- Built a basic layout around `GroupBox`, `HStack`, and related SwiftUI containers.
- Implemented timer-based sending and basic enable/disable behavior.
- Added random generation between configured minimum and maximum values.
- Confirmed `Grid`, `GridRow`, and `GroupBox` as a workable macOS layout approach.

### 13 June 2025

- Built the wind view around TWD, heading, TWS, and boat speed.
- Calculated, displayed, and transmitted derived wind values.
- Made GPS movement depend on SOG and COG.
- Identified drift support as future work.

### 14 June 2025

- Redesigned the app with a sidebar.
- Added the status bar.
- Added anemometer and compass visuals.
- Identified the visuals and structure as needing refactor/polish.

### 15 June 2025

- Improved resizing behavior.
- Added wind/metric cards with better fixed-size behavior.
- Added an NMEA output console in a sidebar.

### 16 June 2025

- Improved NMEA console resizing.
- Rearranged parts of the UI.
- Added sensor toggle switches for wind, speed, compass, and GPS.
- Started the wind setup page.
- Created `ViewKit` for reusable UI formatting helpers.

### 17 June 2025

- Split the NMEA logic into multiple files.
- Added help buttons and contextual information in the wind view.
- Expanded support for different sentences.
- Refactored `WindConfig` for readability.

### 18 June 2025

- Improved logic control around when values are calculated and displayed.
- Prevented several values from showing when related toggles were off.
- Added optional random generation behavior.
- Cleaned up live preview behavior.
- Locked wind sentence toggles and inputs based on dependencies.
- Added warnings and fallback messaging when wind simulation was not active.

### 19 June 2025

- Completed the main wind logic path.
- Made the timer adjustable in real time.
- Kept values calculated even when not sent, while dimming non-transmitted values in the UI.

### 24 June 2025

- Reworked metric handling into `SimulatedValue`.
- Added `SimulatedValueType`.
- Split booleans into `sensorToggles` and `sentenceToggles`.
- Expanded the control dashboard with TWD and TWS sliders.

### 25 June 2025

- Implemented gyro compass support.

### 26 June 2025

- Investigated SwiftUI hover cursor behavior during resize interactions.
- Chose to leave cursor hints out for now due to refresh-related issues.

### 1 July 2025

- Reached a decent base for wind, hydro, heading, and core sensors.
- Made GPS operational at a basic level.
- Updated the UI for different GPS sentences.
- Identified NMEA-side sentence-building logic as unfinished.

### 4 October 2025

- Fixed wind behavior so AWA and AWS could be sent based on TWD/TWS when speed is missing or zero.
- Started a new map-centric design with surrounding toolbars.

### 6 October 2025

- Added leading and trailing dashboard panels.
- Moved the left side toward active control and the right side toward read-only display.
- Continued experimenting with map integration.

## Visual Direction

Brand palette notes from the project:

- black
- turquoise
- silver
- red
- royal purple

Intended tone:

> A bold and timeless palette blending black’s strength, turquoise’s calm confidence, silver’s elegance, red’s power, and royal purple’s triumph.

This visual direction is useful, but it should stay secondary to product credibility. The simulator must become trustworthy before presentation polish becomes the main focus.

## Recommended Next Step

Before more UI work, portfolio work, or demo-video work, the next engineering milestone should be:

1. run the manual interoperability checklist against the external reader from the improved dashboard
2. record any remaining mismatches by sentence family and transport mode
3. fix those defects and add targeted regression tests for each one

Without that pass, the app risks looking more finished than it has been proven to be in real receiver conditions.

Status note:

- The engine/persistence/dashboard foundation milestone is now complete enough for realistic bench testing.
- The next practical milestone is external-reader validation and sentence-level cleanup based on observed mismatches.
