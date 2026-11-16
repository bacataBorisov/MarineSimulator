# Session Cache

Last updated: 2026-11-16

## Current Objective

Workflow: direct single-chat execution (explain plan + architectural fit first, implement directly, user smoke-tests). Proof-of-concept CSV export (`ExperimentDatasetExporter`, `NSSavePanel` `readwrite` entitlement, `Export CSV…` / `Export Truth…` in `Diagnostics`) and offline polar-recovery test (`PolarRecoveryProofOfConceptTests`) passed tests and user smoke-testing and are committed.

## Constraints

Direct single-chat workflow; user is external smoke-test verifier. `Manual` stays ephemeral; all other pages use retained AppKit hosts with one shared `ConsolePanelView` in `MainView`. Check local HIG docs before UI proposals.

## Next

1. Review/refine professor proposal plan in Bulgarian with the user.
2. On user instruction, proceed to full M4 (JSON scenario library, dataset replay, and estimator integration) and M5 (scientific review).
