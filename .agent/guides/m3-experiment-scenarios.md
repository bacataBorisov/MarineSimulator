# M3.2 — Experiment scenario contract

Status: **implemented; data contract only.**

## Purpose

An experiment must be describable independently of the live operator settings. Its record states which polar the estimator receives, which polar generates hidden vessel truth, the random seed, the environmental program, sample cadence, and the boundary of future output.

## V1 record

`ExperimentScenario` contains:

- `formatVersion` (currently 1), stable id, name, and seed;
- reference and hidden `BoatProfile` values as separate fields;
- a steady true-wind program;
- an inert set-and-drift current declaration for the future current model;
- duration and sample interval; and
- an `ExperimentOutputContract` listing permitted measurement fields. It defaults to timestamp, TWD, TWS, true heading, and STW; ground-truth export is false.

## Boundary

The hidden polar is a simulator truth input only. It is not an NMEA field and must not enter an estimator-input export. The contract itself does not persist to JSON files, change a runtime, alter a normal user session, add a UI, or export data.

## Verification

`TruthSeparationTests.experimentScenarioKeepsTruthSeparateAndSanitizesInputs` checks versioning, wind/current normalization, measurement deduplication, disabled truth export, and Codable round-trip.

## Next decision

Define how a scenario is applied to a clean simulation state and how static wind commands are sequenced over time. Do not make current active until its kinematic convention and validation tests are agreed.
