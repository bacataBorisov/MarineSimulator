# Context pack

Profile: **normal**

## Scan

- id: 5
- type: incremental

## Recent changes

- `AGENTS.md` — modified
- `Docs/CompletedTasks.md` — modified
- `Docs/CurrentTasks.md` — modified
- `Docs/FutureTasks.md` — modified
- `Docs/ProjectOverview.md` — modified
- `MarineSimulatorTests/NMEASimulatorEngineTests.swift` — modified
- `Model/BoatProfile.swift` — modified
- `NMEA/NMEANumericFormatting.swift` — new
- `NMEA/NMEASimulator+SentenceBuilder.swift` — modified
- `NMEA/NMEASimulator.swift` — modified
- `README.md` — modified
- `Utilities/FormatKit.swift` — modified
- `Utilities/Shapes.swift` — modified
- `Utilities/ViewKit.swift` — modified
- `Views/ConsoleView.swift` — modified
- `Views/Dashboard/BoatMapPreview.swift` — modified
- `Views/Dashboard/ControlCategory.swift` — modified
- `Views/Dashboard/DashboardChrome.swift` — new
- `Views/Dashboard/DashboardView.swift` — modified
- `Views/Dashboard/WindCompass.swift` — modified
- `Views/HelpViews/ManualView.swift` — modified
- `Views/MainView.swift` — modified
- `Views/WindCompassView/AnemometerView.swift` — modified
- `Views/WindCompassView/CompassView/CompassView.swift` — modified

## Sample chunks

### `.gitignore`
- lines 1–68 `0cdcfba978cb…`
  # Xcode & macOS
  .DS_Store
  *.swp
  *.lock
  *.xcuserstate
  *.xcscmblueprint
  *.xccheckout
  *.xcuserdatad

### `AGENTS.md`
- lines 1–17 `f8eccae249ea…`
  # Agent Guidance
  
  Source of truth for agent workflow lives in `.agent-os/context/`.
  
  Required session flow:
  
  - Run `.agent-os/context/begin-chat.md` at the start of every new session.
  - Run `.agent-os/context/end-chat.md` when the user is ending the session or explicitly starting fresh.

### `AGENT_OS.md`
- lines 1–38 `9465408a45c4…`
  # Agent OS output (this repository)
  
  The tooling stores generated files under **`.agent-os/`**. **Finder** and **Terminal** can always see them; **Xcode** needs two separate ideas (below).
  
  ## Xcode: why new files do not appear automatically
  
  The **Project navigator** is not a full folder listing. It only shows files that are **members of the `.xcodeproj`** (listed in the project file). Creating **`AGENT_OS.md`** on disk does **not** add it to the project.
  

### `App/MarineSimulator.swift`
- lines 1–40 `47f5e4f492f2…`
  //
  //  NMEASimulatorApp.swift
  //  NMEASimulator
  //
  //  Created by Vasil Borisov on 7.06.25.
  //
  
  import SwiftUI

### `Docs/CompletedTasks.md`
- lines 1–71 `8fdd3c8b795a…`
  # Completed Tasks
  
  This file tracks finished work that should not remain in the active queue.
  
  ## Completed
  
  - [x] Convert project notes into a structured project overview document.
  - [x] Introduce a coherent simulation tick that produces one snapshot per cycle.

### `Docs/CurrentTasks.md`
- lines 1–62 `2e62f96dc443…`
  # Current Tasks
  
  These are the tasks currently in progress or next in line for the active work stream.
  
  Agent handoff reference:
  
  - Scan-backed agent handoff lives in `.agent-os/state/current-handoff.md` (refresh with `agentos handoff update`).
  - Use this file (`Docs/CurrentTasks.md`) for product/project task tracking and `.agent-os/context/` for editable session workflow and memory.

### `Docs/FutureTasks.md`
- lines 1–37 `20b3aee86291…`
  # Future Tasks
  
  This is the task pool for work that is planned but not currently active.
  
  ## Engine
  
  - [ ] Add isolated wind modes so AWA/TWA/TWD/TWS can be driven independently when needed.
  - [ ] Add simulator mode and read/ingest mode.

### `Docs/InstructionManual.md`
- lines 1–100 `e67fc0470df0…`
  # Instruction Manual
  
  This manual is the operator reference for MarineSimulator.
  
  ## Purpose
  
  MarineSimulator simulates marine instrument data with an emphasis on NMEA 0183 workflows for navigation app testing on macOS.
  
- lines 101–200 `1579c1ad9359…`
  ## Transport Diagnostics
  
  The app shows transport information in two places:
  
  - toolbar status for the latest state
  - console transport view for recent event history
  
  Typical meanings:

### `Docs/ManualTestChecklist.md`
- lines 1–52 `8e36b43f738e…`
  # Manual Test Checklist
  
  Use this checklist when validating the simulator against an external NMEA reader or device.
  
  ## Output And Transport
  
  - [ ] Verify UDP output reaches a local reader on `127.0.0.1` with the expected port.
  - [ ] Verify TCP output reaches a local reader that expects a stream socket.

### `Docs/ProjectOverview.md`
- lines 1–100 `9987a70f7dc5…`
  # Marine Simulator
  
  ## Purpose
  
  Marine Simulator is a macOS app for simulating onboard marine navigation sensors and transmitting NMEA data to external applications over IP networking.
  
  The project exists to provide a better test environment than a simple script-based simulator, especially for validating navigation software such as Extasy Complete Navigation when real boat time is limited.
  
- lines 101–200 `30fae27ac607…`
  ### Core Simulation
  
  - [ ] Refactor the simulator to produce one coherent state snapshot per tick.
  - [ ] Add logic for isolated wind modes such as direct AWA/TWA cases instead of deriving everything from TWD.
  - [ ] Add damping or optional filtering for more realistic instrument behavior.
  - [ ] Add preset sea/weather modes such as calm, breezy, and storm.
  - [ ] Validate sentence correctness more rigorously.
  - [ ] Add optional invalid/corrupted sentence simulation for receiver robustness testing.

### `LICENSE`
- lines 1–21 `5be1d5d336fc…`
  MIT License
  
  Copyright (c) 2025 Vasil Borisov
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the “Software”), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell

### `MarineSimulator.xcodeproj/xcuserdata/bacataborisov.xcuserdatad/xcschemes/xcschememanagement.plist`
- lines 1–19 `0e004894ee32…`
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
  	<key>SchemeUserState</key>
  	<dict>
  		<key>MarineSimulator.xcscheme_^#shared#^_</key>
  		<dict>

### `MarineSimulatorTests/NMEASimulatorEngineTests.swift`
- lines 1–100 `60b81bfd7995…`
  import Foundation
  import Testing
  @testable import MarineSimulator
  
  struct NMEASimulatorEngineTests {
      @Test
      func checksumMatchesKnownSentence() {
          let simulator = NMEASimulator(userDefaults: isolatedDefaults())
- lines 101–200 `820ba3b46b58…`
  },
            "sensorToggles": {
              "hasAnemometer": true,
              "hasCompass": true,
              "hasGyro": true,
              "hasGPS": true,
              "hasEchoSounder": true,
              "hasSpeedLog": true,

### `MarineSimulatorTests/OpenMeteoWeatherServiceTests.swift`
- lines 1–100 `4c39f5aa782a…`
  import Foundation
  import Testing
  @testable import MarineSimulator
  
  @Suite(.serialized)
  struct OpenMeteoWeatherServiceTests {
      @Test
      func fetchWeatherDecodesMarineHourlyTimestampsWithoutTimeZoneSuffix() async throws {
- lines 101–200 `04d5db28aaf2…`
  #expect(items["current"] == "wind_speed_10m,wind_direction_10m")
          #expect(items["wind_speed_unit"] == "kn")
          #expect(items["timezone"] == "GMT")
          #expect(items["cell_selection"] == "sea")
      }
  
      @Test
      func metNorwayFallbackProvidesGlobalWindWhenOpenMeteoTimesOut() async throws {

### `MarineSimulatorUITests/MarineSimulatorUITests.swift`
- lines 1–43 `c214eabca6f0…`
  //
  //  NMEASimulatorUITests.swift
  //  NMEASimulatorUITests
  //
  //  Created by Vasil Borisov on 7.06.25.
  //
  
  import XCTest

### `MarineSimulatorUITests/MarineSimulatorUITestsLaunchTests.swift`
- lines 1–33 `5cae2a2e8e21…`
  //
  //  NMEASimulatorUITestsLaunchTests.swift
  //  NMEASimulatorUITests
  //
  //  Created by Vasil Borisov on 7.06.25.
  //
  
  import XCTest

### `Model/BoatProfile.swift`
- lines 1–100 `abdfc00fc218…`
  import Foundation
  
  enum BoatSpeedMode: String, Codable, CaseIterable, Identifiable {
      case manual
      case estimated
  
      var id: String { rawValue }
  
- lines 101–200 `5fb54daebe0a…`
  windSpeeds: [6, 8, 10, 12, 16, 20],
                  angles: [35, 45, 60, 75, 90, 110, 135, 150, 165],
                  speeds: [
                      [4.0, 4.9, 5.5, 5.8, 5.7, 5.5, 5.1, 4.5, 3.9],
                      [4.9, 5.8, 6.6, 7.0, 7.1, 6.8, 6.3, 5.6, 4.9],
                      [5.4, 6.4, 7.4, 8.0, 8.2, 8.0, 7.5, 6.7, 5.6],
                      [5.8, 6.9, 8.0, 8.7, 9.0, 8.9, 8.3, 7.5, 6.1],
                      [6.1, 7.3, 8.4, 9.2, 9.6, 9.8, 9.2, 8.2, 6.8],

### `Model/GPSData.swift`
- lines 1–40 `baf26d012a3d…`
  //
  //  GPSData.swift
  //  NMEASimulator
  //
  //  Created by Vasil Borisov on 13.06.25.
  //
  
  

### `Model/LiveWeather.swift`
- lines 1–61 `fc368d54d967…`
  import Foundation
  
  enum WeatherSourceMode: String, Codable, CaseIterable, Identifiable {
      case manual
      case liveWeather
  
      var id: String { rawValue }
  

### `Model/OutputEndpoint.swift`
- lines 1–62 `dc1ca73eed6f…`
  import Foundation
  
  enum NetworkTransport: String, Codable, CaseIterable, Identifiable {
      case udp
      case tcp
  
      var id: String { rawValue }
  }
