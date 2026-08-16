# Session Cache

Last updated: 2026-08-15

## Current Objective

Connection: carded output sections; primary output renameable and toggleable (no longer forced on).

## Product State

- Dashboard map Start/Stop pill removed (toolbar only).
- Console unmounts content while collapsed (no flash); stats bar labeled Rate/Total/Tick with help.
- Connection uses spaced card layout (not cramped Form LabeledContent).
- SensorToggleGrid uses adaptive LazyVGrid (no ViewThatFits clip).
- App `.tint(.accentColor)`; switches use `.controlSize(.large)`.
- GPS selector map recenters on boat coordinate.

## Next

1. Manual pass: Connection / Simulation / GPS / console collapse.
2. Optional: delete leftover `ConfigurationView` if unused after Connection/Simulation split.
3. Optional: remove duplicate green/cyan status tints that fight system accent.

## Notes

- Progressive lag fix still in tree (coalesced UI apply + 400-row console).
- AccentColor asset is empty → resolves to system accent.
