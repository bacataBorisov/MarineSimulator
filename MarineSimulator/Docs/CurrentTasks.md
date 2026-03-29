# Current Tasks

These are the tasks currently in progress or next in line for the active work stream.

## Active

- [ ] Add configuration UI support for multiple output endpoints.
- [ ] Persist last-used simulator settings and endpoint configuration with `UserDefaults`.
- [ ] Expose the new engine foundation safely through the current UI without regressing existing behavior.

## Engineering Notes

- The engine now produces one coherent simulation snapshot per cycle.
- Sentence scheduling now happens per sentence type instead of by coarse bundles.
- UDP output is now modeled as endpoints and can grow into multi-destination output.
- TCP is modeled at the data layer but not implemented yet.
