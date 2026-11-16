# Marine instruments

Status: **inventory of the instruments this repository represents, plus the measurement model.** In prepared experiments, `ExperimentInstrumentRuntime` calls `ExperimentSensorModel.measure` on each new simulation timestamp and `NMEASimulator+SentenceBuilder` reads `snapshot.experimentPublication`. Normal operator sessions leave `experimentPublication` nil.

A physical instrument senses one quantity. A derived value is computed from other readings. A communication flag only chooses whether a sentence is sent. The uniform error law below is an experiment bound. **Literature reference required** before a thesis treats it as a transducer specification. No manufacturer accuracy is stated here.

## How a reading is formed

`ExperimentSensorModel` keeps one `ExperimentRandomGenerator` per channel. The seed is `experimentSeed xor (0x9E3779B97F4A7C15 * channel)`. A new model starts at the first draw. Each `measure` call advances every channel once, including a channel whose reading is then discarded because an input is missing or the instrument is off. Channels 1–4 are unchanged from M3.4.1c.

| Channel | Instrument |
|---|---|
| 1 | Apparent wind speed |
| 2 | Apparent wind angle |
| 3 | Speed through water |
| 4 | True-heading instrument |
| 5 | Magnetic compass |

```text
measured = ideal + bias + noise
noise ~ Uniform[-A, +A)
```

Heading and compass results are then wrapped with `normalizeAngle` into `[0, 360)`. Bias and amplitude default to zero. A non-finite bias or amplitude is treated as zero. `InstrumentAvailability` defaults both heading instruments to on. A false flag returns nil for that instrument and does not copy physical truth into the gap. It does not read `SensorToggleStates`. A later integration can map `hasGyro` to `trueHeadingInstrument` and `hasCompass` to `magneticCompass`.

The forward apparent wind still uses the physical true heading. Calculated true wind direction uses the true-heading instrument only.

## Magnetic compass

Established navigation, east-positive, matching `SimulationEngine` when it converts a maneuver heading:

```text
magnetic = normalizeAngle(trueHeading − variation)
compass  = normalizeAngle(magnetic − deviation)
measuredCompass = normalizeAngle(compass + bias + noise)
```

Variation and deviation are each applied once. Course over ground is not an input. Zero variation and zero deviation are real references. A missing or non-finite true heading, variation, or deviation leaves the compass nil.

A future HDG sentence can use three separate fields:

| HDG field | Value |
|---|---|
| Heading | `magneticCompassHeadingDegrees`, the compass card |
| Deviation | the supplied east-positive deviation, not added again |
| Variation | the supplied east-positive variation, not added again |

A receiver that honors those signs recovers `true = compass + deviation + variation`. A prepared experiment publishes that card in HDG and leaves deviation and variation in their own fields. A normal session still publishes `snapshot.magneticHeading`, the magnetic course, beside deviation. A receiver that adds that deviation shifts the normal heading by the deviation.

The geographic variation formula and `sin(heading * 1.7°) * 1.2°` stay in `SimulationEngine`. The measurement model does not replace them. It uses the numbers the caller supplies. **Unverified** against the World Magnetic Model. The deviation sine is a heuristic, not a deviation card.

## True-heading instrument

Channel 4 is unchanged:

```text
measuredTrueHeading = normalizeAngle(physicalTrueHeading + bias + noise)
TWD = normalizeAngle(measuredTrueHeading + TWA)
```

This instrument observes `VesselTruth.trueHeading` directly. It does not read the compass card, variation, or deviation. It is the measurement behind a future HDT value.

It is not a complete instrument of any of these classes:

| Class | What this model does not have |
|---|---|
| Gyrocompass | Earth-rate north seeking, latitude error, settling |
| GNSS heading sensor | Antenna baseline, motion requirement |
| AHRS / IMU | Rate integration, drift, alignment |

No settling time or accuracy number is invented. The live gyro field still copies physical true heading. This channel is not that copy.

## Instrument inventory

### Masthead wind instrument

1. A cup or ultrasonic anemometer and a wind vane measure the wind at the masthead in the boat frame.
2. The physical quantities are apparent wind speed and apparent wind angle.
3. Truth is water-relative true wind, physical true heading, and speed through water. The model builds the ideal apparent wind from those.
4. Apparent wind is primary. True wind speed, true wind angle, and true wind direction are calculated.
5. `ExperimentSensorModel` applies bias and noise, then inverts the vector. The sentence path still derives apparent wind from the snapshot with no sensor error.
6. `hasAnemometer`. Off clears `twd` and `tws` and drops MWV. The wind redraw still updates `EnvironmentTruth`.
7. MWV relative uses snapshot apparent wind. MWV true, MWD, and VPW use snapshot true wind. MWD also prints a magnetic direction by subtracting variation.
8. The standalone model has bias and uniform noise on apparent wind. The 1 Hz wind redraw is physical, not this error.
9. No delay, dropout, heel, upwash, or calibration table. The live sentences do not use the model.
10. Call `measure` after a tick and keep the result beside the snapshot. Do not write it back into wind truth.

### Speed log

1. A paddlewheel or ultrasonic log measures speed through the water along the hull.
2. The quantity is speed through water.
3. Truth is `VesselTruth.speedThroughWaterKnots`.
4. The log is primary. Voyage distance is a sum of that speed while the log is on.
5. The model adds bias and noise. The tick copies truth into `speed.value` when the log is on.
6. `hasSpeedLog`. Off nils the instrument field. Truth and position still move. Log distance stops.
7. VHW carries the log speed. VLW carries the distances. VBW splits water speed along heading. A nil boat speed suppresses sentence apparent wind.
8. Model bias and noise exist off the tick. `speed.offset` is a physical polar penalty, not a log error.
9. No calibration factor, no fouling drift, no dropout.
10. Keep the log error independent of speed over ground.

### Magnetic compass

1. A magnetic compass aligns to the local magnetic field.
2. The quantity is the compass-card heading.
3. Truth is physical true heading, plus a supplied variation and a supplied deviation.
4. The card is primary. Magnetic and true heading are recovered only by adding the separate deviation and variation fields.
5. Channel 5, as written above. The live path stores the magnetic course and prints deviation beside it.
6. `hasCompass`. Off nils the magnetic instrument field. Steering still uses true heading.
7. HDG. VHW can also print a magnetic heading. The live HDG heading is not the compass card.
8. The model has bias and noise on the card only. Live deviation is the sine heuristic and is not random. Variation is the geographic cartoon and it steers, because the 1 Hz sample is stored as magnetic heading and true heading is magnetic plus variation.
9. No deviation card, no dip, no heeling error. Live HDG can be misread by one deviation.
10. Point HDG at the compass card and leave deviation and variation as separate fields. Do not fold them into the heading number.

### True-heading instrument

1. The limited abstraction is a sensor that reports true heading. The gyro switch and HDT are its live counterparts. The dynamics of a gyrocompass are not modeled.
2. The quantity is true heading, degrees clockwise from true north.
3. Truth is `VesselTruth.trueHeading`.
4. The reading is primary. Calculated true wind direction uses it. It is not derived from the compass.
5. Channel 4. In a prepared experiment, HDT publishes this reading and does not fall back to the compass. A normal session still copies physical true heading into the gyro field.
6. `hasGyro`. Off nils the gyro field. HDT then falls back to magnetic heading plus variation. Steering is unchanged. In the standalone model, switching the instrument off returns nil and does not fall back.
7. HDT and ROT. ROT is the backward difference of steered true heading, not a measured rate.
8. Channel 4 bias and noise. The live gyro has neither.
9. No earth rate, no latitude error, no drift, no rate-gyro noise.
10. Publish this channel as HDT only when the gyro instrument is on. Do not fill it from the compass.

### GNSS receiver

1. A GNSS receiver solves position from satellite ranges. Course over ground and speed over ground are receiver outputs, not a heading sensor.
2. The quantities are latitude, longitude, speed over ground, and course over ground, plus a synthetic satellite view.
3. Truth is the spherical step in `GPSData.updatePosition`. When `ExperimentCurrentProgram.driftKnots == 0` (normal sessions), speed over ground equals water speed and course over ground equals true heading; with active current, `simulatedMovement` adds the set/drift vector to water velocity.
4. Position is integrated from physical motion. The satellite counts are a display model.
5. No measurement error. `simulatedGPSSignal` fills fix quality, DOP, and satellites from time and position.
6. `hasGPS`. Off drops the GPS sentences. Position still integrates. `shouldSendGNSS` is stored and unused.
7. RMC, GGA, VTG, GLL, GSA, GSV, ZDA. RMB and XTE are waypoint arithmetic, not a receiver.
8. None on the fix. The satellite counts are deterministic functions, not noise.
9. No pseudorange error, no multipath, no heading-from-baseline.
10. A GNSS error model is a later task. Do not use course over ground as compass or gyro heading.

### Depth sounder

1. An echo sounder times a sound pulse to the bottom.
2. The quantity is depth below the transducer.
3. Truth is `EnvironmentTruth.depthMeters`.
4. Depth is primary. The offset in DPT is an installation field, not a second measurement.
5. The 1 Hz redraw replaces physical depth. The instrument field is cleared when the sounder is off.
6. `hasEchoSounder`.
7. DBT and DPT. DPT is suppressed when the offset magnitude is above 99 m.
8. No bias or noise. The offset is operator configuration.
9. No draft model, no dropout, no false bottom.
10. A depth error belongs on a later channel. Do not change the offset into random noise without saying so.

### Sea-water temperature

1. A thermistor in the seawater intake.
2. The quantity is sea temperature.
3. Truth is `EnvironmentTruth.seaTemperatureCelsius`.
4. Primary.
5. The 1 Hz redraw writes truth. The instrument field follows it when the sensor is on.
6. `hasWaterTempSensor`.
7. MTW.
8. None beyond the physical redraw.
9. No calibration error.
10. Leave it off the wind and heading streams.

### Air temperature, humidity, and barometer

1. These are cabin or mast sensors for air temperature, relative humidity, and barometric pressure.
2. Each measures its own scalar.
3. Truth is the matching `EnvironmentTruth` field.
4. Primary. None of them enters the wind vector.
5. Manual mode samples them on `measurementRandomGenerator`. Live weather jitters a forecast. The snapshot stores the instrument fields.
6. `hasAirTempSensor`, `hasHumidtySensor`, and `hasBarometer` default off.
7. `MDA` and `XDR` sentences emit atmospheric readings (plus water temperature in `MDA`) when enabled and atmospheric sensors are on (`Views/HelpViews/Wind/MDAHelpView.swift`, `XDRHelpView.swift`).
8. The manual sample is physical replacement, not a sensor error on a fixed truth.
9. No calibration error or sensor delay.
10. Keep their random stream separate from the physical wind stream.

### Values that are not instruments

| Value | What it is |
|---|---|
| Calculated true wind | Inverse of apparent wind and the log, then the true-heading instrument for direction |
| VPW | `TWS * cos(TWA)` at sentence time |
| ROT | Difference of steered true heading |
| VBW transverse | A component of speed relative to heading, separating water speed from GPS ground track when current is active |
| VLW | An instrument counter, not `VesselTruth` |
| Sailing-state label | A band name. It does not enter speed |
| Wire faults | Damage to bytes after a sentence exists |
| DSC | `shouldSendDSC` is stored and unused |

## Inconsistencies left in place

- A normal HDG heading is the magnetic course, while deviation is also printed. An experiment HDG heading is the compass card. The two sessions do not use the same heading field.
- The chart heading resolver prefers the gyro, then magnetic heading without variation, then course over ground. The NMEA wind resolver prefers magnetic heading plus variation, then the gyro. Those two paths can disagree by the variation.
- HDT falls back to magnetic heading plus variation when the gyro field is nil. The standalone model does not. An unavailable true-heading instrument stays nil.
- The 1 Hz heading sample is stored as magnetic heading and then steers. That is physical variation, not compass noise.
- Compass deviation does not steer and is not the model's bias.

## Assumptions and limits

The boat frame has no heel. Steady current (`ExperimentCurrentProgram`) separates `SOG`/`COG` from `STW`/`HDT` in experiments, while normal operator sessions run with zero current. The true-heading instrument and the compass do not feed steering, the polar, or the position step. **Unverified** against a compass card, a gyrocompass manual, or a masthead instrument.
