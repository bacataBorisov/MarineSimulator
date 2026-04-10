# Context pack

Profile: **normal**

## Scan

- id: 3
- type: incremental

## Recent changes

- `Docs/CompletedTasks.md` — new
- `Docs/CurrentTasks.md` — new
- `Docs/FutureTasks.md` — new
- `Docs/InstructionManual.md` — new
- `Docs/ManualTestChecklist.md` — new
- `Docs/ProjectOverview.md` — new
- `MarineSimulator/Docs/CompletedTasks.md` — deleted
- `MarineSimulator/Docs/CurrentTasks.md` — deleted
- `MarineSimulator/Docs/FutureTasks.md` — deleted
- `MarineSimulator/Docs/InstructionManual.md` — deleted
- `MarineSimulator/Docs/ManualTestChecklist.md` — deleted
- `MarineSimulator/Docs/ProjectOverview.md` — deleted
- `README.md` — modified

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
- lines 1–15 `b394bb75acb5…`
  # Agent Guidance
  
  Source of truth for agent workflow lives in `.agent-os/context/`.
  
  Required session flow:
  
  - Run `.agent-os/context/begin-chat.md` at the start of every new session.
  - Run `.agent-os/context/end-chat.md` when the user is ending the session or explicitly starting fresh.

### `AGENT_OS.md`
- lines 1–37 `f1cb2b94289d…`
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
- lines 1–50 `5a4d3af8e7c7…`
  # Completed Tasks
  
  This file tracks finished work that should not remain in the active queue.
  
  ## Completed
  
  - [x] Convert project notes into a structured project overview document.
  - [x] Introduce a coherent simulation tick that produces one snapshot per cycle.

### `Docs/CurrentTasks.md`
- lines 1–50 `79338fd7ce79…`
  # Current Tasks
  
  These are the tasks currently in progress or next in line for the active work stream.
  
  Agent handoff reference:
  
  - Scan-backed agent handoff lives in `.agent-os/state/current-handoff.md` (refresh with `agentos handoff update`).
  - Use this file (`Docs/CurrentTasks.md`) for product/project task tracking and `.agent-os/context/` for editable session workflow and memory.

### `Docs/FutureTasks.md`
- lines 1–35 `8c4b1cf1d4d3…`
  # Future Tasks
  
  This is the task pool for work that is planned but not currently active.
  
  ## Engine
  
  - [ ] Add isolated wind modes so AWA/TWA/TWD/TWS can be driven independently when needed.
  - [ ] Add damping/filtering options for instrument behavior.

### `Docs/InstructionManual.md`
- lines 1–100 `414a2026a7de…`
  # Instruction Manual
  
  This manual is the operator reference for MarineSimulator.
  
  ## Purpose
  
  MarineSimulator simulates marine instrument data with an emphasis on NMEA 0183 workflows for navigation app testing on macOS.
  
- lines 101–190 `c25ec44f4434…`
  ## Multi-Endpoint Use
  
  You can stream to more than one destination at once.
  
  Typical use cases:
  
  - one simulator app on the Mac
  - one real device over Wi-Fi or Ethernet

### `Docs/ManualTestChecklist.md`
- lines 1–52 `8e36b43f738e…`
  # Manual Test Checklist
  
  Use this checklist when validating the simulator against an external NMEA reader or device.
  
  ## Output And Transport
  
  - [ ] Verify UDP output reaches a local reader on `127.0.0.1` with the expected port.
  - [ ] Verify TCP output reaches a local reader that expects a stream socket.

### `Docs/ProjectOverview.md`
- lines 1–100 `41feb72d457c…`
  # Marine Simulator
  
  ## Purpose
  
  Marine Simulator is a macOS app for simulating onboard marine navigation sensors and transmitting NMEA data to external applications over IP networking.
  
  The project exists to provide a better test environment than a simple script-based simulator, especially for validating navigation software such as Extasy Complete Navigation when real boat time is limited.
  
- lines 101–200 `9e96b236409f…`
  - [ ] Improve VHW logic:
    - use gyro heading when available
    - otherwise derive true heading from magnetic heading plus variation
  - [ ] Add simulator mode and read mode so the app can also ingest live sensor/network data.
  
  ### Networking
  
  - [ ] Add TCP/IP output option.

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
- lines 101–200 `bd675a119e1e…`
  },
            "sensorToggles": {
              "hasAnemometer": true,
              "hasCompass": true,
              "hasGyro": true,
              "hasGPS": true,
              "hasAIS": false,
              "hasEchoSounder": true,

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

### `Model/GPSData.swift`
- lines 1–40 `baf26d012a3d…`
  //
  //  GPSData.swift
  //  NMEASimulator
  //
  //  Created by Vasil Borisov on 13.06.25.
  //
  
  

### `Model/OutputEndpoint.swift`
- lines 1–62 `dc1ca73eed6f…`
  import Foundation
  
  enum NetworkTransport: String, Codable, CaseIterable, Identifiable {
      case udp
      case tcp
  
      var id: String { rawValue }
  }

### `Model/SensorToggleStates.swift`
- lines 1–44 `98936ccd5aca…`
  //
  //  SensorToggles.swift
  //  NMEASimulator
  //
  //  Created by Vasil Borisov on 24.06.25.
  //
  
  import Foundation

### `Model/SentenceToggleStates.swift`
- lines 1–48 `1265588ff060…`
  //
  //  SentenceToggleStates.swift
  //  NMEASimulator
  //
  //  Created by Vasil Borisov on 24.06.25.
  //
  
  

### `Model/SimulatedValue.swift`
- lines 1–100 `9d9332f6b695…`
  import Foundation
  
  /// Enum to represent different types of navigational metrics
  enum SimulatedValueType: String, CaseIterable, Codable, Identifiable {
      case magneticCompass
      case gyroCompass
      case windDirection
      case windSpeed
- lines 101–117 `509be24e6b5d…`
  // Limit offset so it never exceeds half of total range
          let maxAllowedOffset = (range.upperBound - range.lowerBound) / 2
          offset = min(offset, maxAllowedOffset)
  
          let generated = Double.random(in: lowerBound...upperBound)
          value = generated
          return generated
      }
