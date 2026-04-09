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
- Live dashboard controls follow the same rule: if a sensor is disabled, the related control surface is disabled too.

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
- auto-restored last-used live simulator values
- named simulation presets for repeatable test baselines
- transport diagnostics and history
- in-app searchable operator manual
- map-first dashboard with overlay control and instrument rails
- console drawer with NMEA and transport modes

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

## Dashboard Workflow

### Presets

The dashboard and configuration area support quick baseline presets such as calm, light weather, and stormy weather. These are intended to shorten repeated manual test setup.

### Control Priority

- If gyro heading is installed, it is treated as the preferred heading source for true-heading-based calculations.
- If no gyro is installed, magnetic heading becomes the active source.

### Sentence Output Pills

The instrument rail shows sentence pills for wind, heading, GPS, and hydro output.

- clicking a pill enables or disables that sentence immediately
- warning styling means the sentence is enabled in configuration but currently blocked by missing dependencies

### Console Drawer

The console is a bottom drawer rather than a full panel.

- drag the drawer upward to expand it
- drag it downward to collapse it
- switch between `NMEA` and `Transport` modes from the drawer header
- NMEA lines now show a transmit timestamp for manual verification

## Known Limits

- TCP behavior is functional and now includes clearer lifecycle reporting and retry cooldowns, but can still be expanded further
- calibration controls for current, variation, and deviation are not exposed yet
- NMEA 2000 is not implemented

## Troubleshooting

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

### Why A Control Is Disabled

If a dashboard control is dimmed or locked, the related onboard sensor is disabled in Configuration. Install the sensor first, then control it from the dashboard.

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
