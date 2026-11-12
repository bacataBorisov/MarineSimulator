# M3.1 — Reproducible experiment seeding

Status: **implemented; seed foundation only.** This slice follows the thesis Rev 0.3 controlled-simulation plan.

## Purpose

Two experiments with matching simulator input, tick timestamps, and a seed must produce the same manually evolved environment and vessel observations. A normal interactive session must keep its existing system-random behavior.

## Contract

- `ExperimentRandomGenerator` is an optional value on `SimulationState`; `nil` means system randomness.
- The manually evolved wind, ambient values, heading, depth, and manual speed use that source during `SimulationEngine.tickSimulation`.
- A seed remains runtime-only. It is not in `SimulatorSettings`, `SimulationInputMirror`, a NMEA sentence, or the product UI.
- Live-weather jitter stays provider-side and unseeded here.
- Wire fault injection stays in `SentenceScheduler` and unseeded here.
- No scenario file, current model, bias/drift model, export format, or experiment runner is part of this slice.

## Verification

`TruthSeparationTests.seededManualEvolutionIsReproducible` advances two separately created states with the same seed and timestamps, and asserts matching environment, vessel, depth, and position outcomes. A distinct seed produces a distinct wind realization.

## Next decision

Before extending the seed contract, define an approved scenario record: its version, seed, reference/hidden polar relation, wind/current program, and which truth and measurement fields are permitted to leave the simulator.
