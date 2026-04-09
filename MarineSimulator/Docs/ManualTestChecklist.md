# Manual Test Checklist

Use this checklist when validating the simulator against an external NMEA reader or device.

## Output And Transport

- [ ] Verify UDP output reaches a local reader on `127.0.0.1` with the expected port.
- [ ] Verify TCP output reaches a local reader that expects a stream socket.
- [ ] Verify two enabled endpoints receive the same sentence stream at the same time.
- [ ] Verify disabling a secondary endpoint stops output to that target without affecting the primary endpoint.
- [ ] Verify transport history shows connect, refusal, waiting, and idle transitions clearly.

## Timer And Lifecycle

- [ ] Verify `Enable Timer = OFF` sends one burst only.
- [ ] Verify `Enable Timer = ON` sends continuously at `1.0 s` by default.
- [ ] Verify changing the global interval while transmitting changes cadence without requiring a restart.
- [ ] Verify stopping transmission immediately halts output and leaves transport status in an idle state.
- [ ] Verify restarting transmission resets trip distance and sentence scheduling as expected.

## Wind

- [ ] Verify `MWD` true wind direction matches the configured TWD in the external reader.
- [ ] Verify `MWV` relative mode reports relative wind, not absolute direction.
- [ ] Verify dashboard wind presentation matches emitted wind sentences for east/west orientation.
- [ ] Verify the external reader agrees with the simulator when `MWV Reference` is set explicitly to `Relative`.

## Heading And Motion

- [ ] Verify `HDG` follows magnetic heading changes.
- [ ] Verify `HDT` follows gyro heading changes.
- [ ] Verify `COG` follows heading in the default no-current setup.
- [ ] Verify `VTG` magnetic course matches true course adjusted by variation.

## GPS And Hydro

- [ ] Verify `RMC`, `GGA`, `GLL`, `GSA`, `GSV`, and `ZDA` are all accepted by the external reader.
- [ ] Verify `VBW` blanks ground fields when GPS is disabled.
- [ ] Verify `VHW` only appears when both a heading source and speed log are enabled.
- [ ] Verify `DPT` disappears when the depth offset is outside the supported range.

## Fault Injection

- [ ] Verify dropped sentences are visible in transport history.
- [ ] Verify delayed sentences appear later rather than disappearing entirely.
- [ ] Verify checksum corruption is rejected by the external reader when enabled.
- [ ] Verify invalid-data mutations trigger degraded or invalid state in the external reader.
