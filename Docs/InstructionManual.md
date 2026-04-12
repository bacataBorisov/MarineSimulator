# Instruction Manual

This manual is the operator reference for MarineSimulator.

## Purpose

MarineSimulator simulates marine instrument data with an emphasis on NMEA 0183 workflows for navigation app testing on macOS.

The current focus is:

- realistic-enough sensor behavior
- reliable multi-endpoint output
- sentence-level control
- visible diagnostics for transport and simulator state

## Core Concepts

### Simulation Tick

The engine produces one coherent snapshot per cycle. All sentences emitted during that cycle are built from the same snapshot so values stay internally consistent.

### Sensors Vs Sentences

- Sensor toggles represent which onboard instruments exist.
- Sentence toggles represent which NMEA outputs are emitted.

If a sentence requires data from sensors that are disabled, the sentence should not be emitted.

### Output Endpoints

An output endpoint is one destination for generated data.

Each endpoint has:

- host
- port
- transport type
- enabled state

You can use multiple endpoints at the same time to feed more than one consumer.

## Network Output

### UDP

Use UDP when the receiver expects datagrams and does not require connection-oriented delivery.

Good for:

- local simulator tools
- lightweight listeners
- multi-destination broadcast-style testing

### TCP

Use TCP when the receiver expects a continuous stream over a persistent connection.

Good for:

- devices or tools that expose a TCP listener
- tests where ordered delivery over one socket matters
- feeding a real device and a simulator with different transport requirements

## Current Features

### Engine

- coherent snapshot-based simulation tick
- sentence scheduling with per-sentence intervals
- multiple output endpoints
- UDP and TCP output
- sentence fault injection
- persistent simulator settings
- transport diagnostics and history
- in-app searchable operator manual

### Dashboard

- map-first layout with collapsible leading controls, trailing instruments, and bottom console
- floating map tools for west/east repositioning and boat recentering
- map tools stay above the map instead of dropping behind the console drawer

### Live Weather

- manual mode remains the default
- live weather mode uses the current GPS position
- V1 live weather currently drives true wind direction, true wind speed, and sea-surface temperature
- provider: Open-Meteo
- if the fetch fails, the simulator keeps the last good live snapshot or falls back to manual behavior

### NMEA 0183 Coverage

Current implemented families include:

- wind
- heading
- hydro
- GPS

Some sentences are already reasonably coherent, but sentence fidelity is still under active improvement.

## Transport Diagnostics

The app shows transport information in two places:

- toolbar status for the latest state
- console transport view for recent event history

Typical meanings:

- `connected`: endpoint is currently working
- `warning`: receiver missing, waiting, or cooling down before reconnect
- `error`: hard failure that needs operator attention
- `idle`: no active transport session

## Multi-Endpoint Use

You can stream to more than one destination at once.

Typical use cases:

- one simulator app on the Mac
- one real device over Wi-Fi or Ethernet
- one recorder/logger process

Example pattern:

- `UDP 127.0.0.1:4950` for a local simulator
- `TCP 192.168.1.50:10110` for another tool or bridge

## External Reader Compatibility

When validating against another app or device, start from a conservative setup:

- UDP unless the receiver explicitly expects TCP
- fault injection disabled
- timer interval at `1.0 s`
- `MWV` in relative mode first
- `MWD` enabled if you want explicit true wind direction

Important distinctions:

- `HDG` follows magnetic heading
- `HDT` follows gyro heading
- `MWV` is relative or true-relative wind, not absolute true wind direction
- `MWD` is the sentence to compare for absolute true wind direction

If a receiver display does not match the simulator, compare raw `MWD`, `MWV`, `HDG`, `HDT`, `VTG`, and `RMC` before trusting the rendered UI.

## Known Limits

- TCP behavior is functional and now includes clearer lifecycle reporting and retry cooldowns, but can still be expanded further
- calibration controls for current, variation, and deviation are not exposed yet
- NMEA 2000 is not implemented

## Troubleshooting

### Map Controls Are Hidden

The map repositioning controls live in a floating toolbar near the top of the map.

If you do not see them:

- enable GPS in Configuration
- check that you are on the dashboard view
- verify the app window is large enough to show the map header area clearly

### Connection Refused

This usually means the simulator is sending to a host and port where nothing is listening.

Check:

- destination IP
- destination port
- receiver is already running
- transport type matches the receiver

### GPS Looks Too Perfect

GPS support sentences are simulated, not backed by a real satellite visibility model yet. They are now coherent, but still synthetic.

### Why Water Speed And GPS Speed Differ

That is intentional. The simulator now separates water-track from ground-track using a simulated current model.

### Live Weather Is Not Updating

Check:

- GPS is enabled
- Weather Source is set to `Live Weather` in Configuration
- the Mac has network access
- the refresh interval or movement threshold has been reached, or you pressed `Refresh Weather`

### Fault Injection

Fault injection can be enabled in Configuration.

Current supported fault types:

- dropped sentences
- delayed sentences
- corrupted checksums
- invalid status/data flags for selected sentences

Use this to verify whether a receiver:

- tolerates missing traffic
- rejects bad checksums
- reacts correctly to invalid GPS/navigation status
- handles delayed or uneven delivery

## Documentation Workflow

When behavior changes, update this file instead of leaving the rule only in code or chat.

Recommended additions:

- sentence-specific behavior notes
- network recipes
- real-device testing notes
- troubleshooting examples
