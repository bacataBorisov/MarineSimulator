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
- persistent simulator settings
- transport diagnostics and history

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

## Known Limits

- TCP behavior is functional but still being hardened for repeated failures
- fault injection is not implemented yet
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

## Documentation Workflow

When behavior changes, update this file instead of leaving the rule only in code or chat.

Recommended additions:

- sentence-specific behavior notes
- network recipes
- real-device testing notes
- troubleshooting examples
