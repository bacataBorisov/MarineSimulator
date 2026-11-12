# M1 data flow

Approved constraint: no new dynamics, wind models, currents, or sensor-error algorithms. Manual and From Wind stay.

```text
setpoints (center / offset / tack command / GPS fix)
        │
        ▼
EnvironmentTruth          VesselTruth
true wind, sea, air       heading, STW, lat/lon, SOG, COG
        │                       │
        └───────────┬───────────┘
                    │ one-way project
                    ▼
        instrument fields + GPSData     ← NMEA snapshot reads only this
                    │
                    ▼
        existing sentence builders, scheduler, UDP/TCP
```

Physics integration stays at 20 Hz (`simulationFastTickInterval`, 0.05 s). Environment and manual sensor redraw stay at 1 s (`environmentEvolutionInterval`). That redraw is still one uniform sample across `center ± offset`, not a small step. Between redraws the tick copies truth back onto the instrument fields, so writing `.value` alone cannot move the boat. NMEA sentence intervals stay independent. UI publish stays at 10 Hz. No extra scheduler.

While transmitting, the map bearing is the true heading of the newest HDT already in the console buffer. A tack samples that runtime heading on the simulation queue before it animates, so the dashboard does not keep a pre-tick gyro.

Fault history is written before an idle `sendAllSelectedNMEA` returns. The simulation queue still hops to the main thread asynchronously, because that queue must not block on main.

GNSS Receiver and DSC Radio stay in saved settings and are disabled in the UI. They do not emit sentences.

A GPS fix is a command. The tick adopts `gpsData` latitude and longitude only when `lastAppliedGPSCoordinateGeneration` differs from `vesselTruth.acceptedCoordinateGeneration`. `syncLiveSetpointsIntoRuntime` writes the same fix into vessel truth when the user is editing coordinates or the generation changed.

`EnvironmentTruth` and `VesselTruth` live on `SimulationState`. They are not copied into NMEA sentences or `SimulationInputMirror`.

Depth and the wire-level fault injector stay on the measurement / sentence side.

`tickSimulation` owns the write order for all four layers, so M1 was implemented in this chat instead of parallel hive edits. Model types stay in `SimulationState.swift` because `Model/` is an explicit Xcode group.
