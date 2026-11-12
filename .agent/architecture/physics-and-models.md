# Physics and models

This note is a starting point for a methodology chapter. It describes the equations the program evaluates. It does not claim that those equations reproduce a real yacht.

A claim is **verified** when a test or a direct reading of the cited function supports it. A claim about the sea, the Farr VPP, or a real Extasy is **unverified** unless a citation is named. Missing theory is marked **Literature reference required**. No literature reference is invented here.

Shared clocks, from `NMEA/NMEASimulator.swift` and `SimulationEngine.environmentEvolutionInterval`:

| Clock | Interval | Role |
|---|---|---|
| Physics tick | 0.05 s | Speed filter, maneuver heading, position. |
| Environment redraw | 1 s | Replaces wind, heading, depth, and manual speed with a new sample. |
| Sentence interval | Per sentence | Does not move the boat. |
| UI publish | 0.1 s | Does not move the boat. |

The first tick in a run has `deltaTime` 0, so position does not advance. Later ticks use the elapsed time between timestamps, capped where a helper says so.

Angles used as compass courses are degrees clockwise from true north, unless a function says magnetic. `normalizeAngle` maps any degree value into `[0, 360)`. `calculateShortestRotation` returns the signed shortest turn in `(-180, 180]`.

## 1. Polar speed lookup

**Purpose.** Map true wind speed and an unsigned true wind angle to a boat speed in knots.

**Kind.** Empirical table plus bilinear interpolation, with a local pinch heuristic. Not a solution of the equations of motion.

**Inputs.** True wind speed in knots. True wind angle in degrees. The caller passes the unsigned fold `abs(calculateShortestRotation(from: trueHeading, to: trueWindDirection))`, which lies in `[0, 180]`.

**Outputs.** Speed in knots, or nil when the profile has no table.

**Algorithm.** `PolarTable.interpolatedSpeed` in `Model/BoatProfile.swift`.

Wind speed is clamped to the first and last tabulated speeds. The angle is folded into `[0, 180]`. Inside the tabulated angle range, speed is the bilinear blend of the four surrounding cells:

```text
s = s00 + (s01 - s00) * u + (s10 - s00) * v + (s00 - s01 - s10 + s11) * u * v
```

where `u` and `v` are the fractions along the wind-speed axis and the angle axis. Below the first tabulated angle `a_min`, the speed at `a_min` is multiplied by `(a / a_min)^2`. The result is not negative.

**Units.** Knots and degrees. The table comment says Farr Yacht Design VPP, Design #354, racing sail plan, rough water, masthead wind. The stored PDF is `Resources/ReferenceDocuments/Extasy/Farr_Design_354_Performance_Prediction.pdf`. **Literature reference required** for treating that table as a validated prediction of the real Extasy. The ORC certificate is a different dataset and is not this table.

**Update.** Algebraic. No time step.

**Parameters.** The embedded speed matrix. Only `BoatProfile.beneteauFirst407` has it (`hasSpeedPolar`). Nimana's table is nil.

**Assumptions.** The unsigned angle is enough. Port and starboard share one curve. Wind is the true wind already stored, not an apparent wind.

**Limitations.** Clamping discards wind outside the table. The pinch factor is a local heuristic. **Unverified** as a hydrodynamic result. Nimana does not borrow this table.

**Validation.** `SimulationPhysicsTests.polarLookupReturnsExpectedValuesAtKnownPoints` expects 7.01 kn at 45° and 12 kn, and 8.18 kn at 90° and 12 kn. `PolarDynamicsTests` checks the instant estimated path against the same table.

## 2. Hidden and reference polars

**Purpose.** Let the boat sail on one polar while an estimator is allowed to see another.

**Kind.** Software separation, not a second physical theory.

**Inputs.** `SimulationState.hiddenPolarOverride`. `SimulationConfig.boatProfile`, copied to `VesselObservation.referenceProfile`.

**Outputs.** The hidden profile selects the table in section 1. The reference profile does not enter that lookup. When the override is nil, the selected profile is both.

**Algorithm.** `SimulationEngine.hiddenPolar` and `hiddenTargetSpeedKnots`. `ExperimentScenarioRunner.prepare` sets the override from `hiddenPolarProfile` and the config profile from `referencePolarProfile`.

If the override is set and that profile has no table, previous speed through water is held. It is not replaced by speed over ground. A normal Nimana session, with a nil override, can still fall through to speed over ground when speed through water is missing.

**Update.** Chosen once per tick. The table evaluation is section 1.

**Assumptions.** The reference identity is what a later estimator may be shown. The hidden identity must not be reconstructed from NMEA, because NMEA does not carry it.

**Limitations.** The snapshot and the sentences still have no polar field. Sail area and certificate provenance are also absent from NMEA.

**Validation.** `ExperimentScenarioRunnerTests.referenceChoiceDoesNotChangeAnExtasyTruthTrajectory` and `MeasurementBoundaryTests.hiddenPolarIndependenceHoldsWithEverySensorOff`.

## 3. Estimated speed composition

**Purpose.** Turn the polar speed into the speed the boat is assigned.

**Kind.** Empirical product of factors. Not a force balance.

**Inputs.** Hidden polar speed `V_polar`. Live-weather flag. `speed.offset` in percent. `PerformanceParameters`: `hullFactor`, `sailFactor`, `trimEfficiency`, `seaStateFactor`. Maneuver retention from section 5.

**Outputs.** Target speed through water, in knots, clamped to the speed-log range.

**Equation.** `hiddenTargetSpeedKnots`:

```text
V_target = V_polar * k_sea * k_offset * k_hull * k_sail * k_trim * k_seaState * k_retention
```

`k_sea` is 0.96 when weather source mode is live weather, otherwise 1. `k_offset` is `max(0.88, 1 - offset / 100)`. The four performance factors default to 1.

**Units.** Knots. `speed.offset` is a dimensionless penalty, not a log error in knots.

**Update.** Once per physics tick, from the current wind truth and steered heading.

**Assumptions.** Factors multiply. They do not depend on which instruments are switched on. Wind input is `EnvironmentTruth`, not the anemometer field.

**Limitations.** `k_sea` and `k_offset` have no derivation in the source. **Literature reference required** before a thesis treats them as sea state or as a performance loss. `speed.offset` is an operator control that changes the boat, not the instrument.

**Validation.** `MeasurementBoundaryTests.speedOffsetScalesEstimatedSpeedAsAPhysicalModifier` expects a 10% offset to scale speed by 0.90.

## 4. Speed response

**Purpose.** Either assign the target immediately or lag toward it.

**Kind.** A linear first-order lag, solved for one step. Heuristic relative to a yacht's surge dynamics.

**Inputs.** Current speed through water, `V_target`, `deltaTime`, `SpeedResponse`, and the two time constants.

**Outputs.** The next speed through water, also copied to the speed-log field when that sensor is on.

**Equation.** `stepSpeed`, used by `respondedSpeed`. Instant mode, the default, sets the speed to `V_target`. First-order mode uses

```text
V(t + dt) = V_target + (V(t) - V_target) * exp(-dt / tau)
```

`tau` is `accelerationTimeConstantSeconds` when the target is at least the current speed, otherwise `decelerationTimeConstantSeconds`. Defaults are 8 s and 4 s. `tau <= 0` assigns the target. Manual mode does not use this filter. On an evolution tick it replaces speed through water with one uniform sample of the speed setpoint.

**Units.** Knots and seconds.

**Update.** Analytic step once per physics tick. This is not a forward-Euler integration of acceleration.

**Assumptions.** One speed state is enough. Added mass, thrust, and drag are absorbed into `tau`.

**Limitations.** **Literature reference required** for identifying `tau` with a real hull. Manual mode ignores the polar. **Unverified** against Extasy trials.

**Validation.** `PolarDynamicsTests` covers instant agreement, the first-order step, and tack retention with a reference Nimana and a hidden Extasy.

## 5. Maneuver speed retention

**Purpose.** Reduce the target speed during a tack or a gybe, then let section 4 recover it.

**Kind.** A prescribed scalar. Not a dynamic stall model.

**Inputs.** Maneuver kind, start time, duration, `tackSpeedRetention`, `gybeSpeedRetention`. Both retentions default to 1, which leaves speed unchanged.

**Equation.** While the maneuver phase is in progress,

```text
k_retention = 1 - (1 - k_min) * sin(pi * progress)
progress = clamp((t - t0) / duration, 0, 1)
```

`k_min` is the tack or the gybe retention. The sine is 0 at both ends and 1 at mid-turn.

**Update.** Evaluated inside `V_target` each tick. Recovery after the maneuver is only the speed filter, not a separate model.

**Assumptions.** The operator chose the minimum. The shape is the same for every boat.

**Limitations.** Retention of 1 is the historical behavior. **Literature reference required** for any claim about speed loss through a real tack. **Unverified.**

**Validation.** `PolarDynamicsTests` for retention below 1. `ManeuverCommandTests` for heading geometry, not for the sine curve.

## 6. Heading sample and steering

**Purpose.** Choose the true heading that steers the boat between maneuvers.

**Kind.** A uniform redraw of magnetic heading, then a heuristic variation. Not a gyrocompass error model and not a yaw ODE.

**Inputs.** Heading center and offset in degrees. GPS latitude and longitude. Timestamp. The previous true heading between redraws.

**Outputs.** `VesselTruth.magneticHeading` and `VesselTruth.trueHeading`. Compass and gyro fields are copies, cleared when those sensors are off.

**Algorithm.** Every 1 s, unless a maneuver is driving the heading, `generateRandomValue` draws

```text
heading ~ Uniform[center - offset, center + offset]
```

clamped to the instrument range. An offset of 0 returns the center and still consumes one random draw. True heading is

```text
psi = normalizeAngle(magneticHeading + variation)
```

and is held until the next redraw. `simulatedMagneticVariation` is

```text
variation = clamp(longitude * 0.16 + sin(latitude) * 6.5 + sin(t / 86400 / 45) * 1.8, -25, 25)
```

with latitude in radians inside the sine, longitude in degrees, and `t` in seconds since the Swift reference date. The result is degrees.

Steering reads `VesselTruth.trueHeading`. It does not read the compass switch.

**Units.** Degrees. Variation is east-positive in the NMEA sentences that print it. **Unverified** against a magnetic model.

**Update.** Replacement every 1 s, not a random walk. Hold on the 20 Hz ticks in between.

**Assumptions.** The redraw is the boat's heading, not an instrument error on top of a fixed heading. That is why disabling the compass does not freeze the heading.

**Limitations.** The variation formula is a smooth geographic cartoon. **Literature reference required** before comparing it with the World Magnetic Model. Compass deviation, `sin(heading * 1.7°) * 1.2°`, is applied only when a compass reading is published. It does not steer the boat. `ExperimentSensorModel` can noise a separate true-heading measurement. This steering path does not read it. Variation and deviation are not that noise.

**Validation.** `MeasurementBoundaryTests.environmentalHeadingRedrawChangesTheTrack` and `eachSensorToggleLeavesTruthAndTimeUnchanged`.

## 7. Maneuver heading

**Purpose.** Turn the boat from one true heading to another on a fixed schedule.

**Kind.** A kinematic smoothstep. Not a yaw-rate controller and not an autopilot that closes on sensor feedback.

**Inputs.** `ActiveManeuver`: start, duration, `fromTrueHeading`, `toTrueHeading`, signed `turnDelta`.

**Equation.** `maneuverHeading`:

```text
s = p^2 * (3 - 2p)
psi(t) = normalizeAngle(from + turnDelta * s)
```

with `p` the same clamped progress as section 5. At the end, the heading is `toTrueHeading`.

The tack and gybe target used by the command path is the mirror

```text
psi_target = normalizeAngle(2 * trueWindDirection - psi_start)
```

`SimulationEngine.mirroredTrueHeading`. A tack's signed turn is the arc that passes through the true wind. A gybe's arc passes through true wind plus 180°, including the long way. The same-tack command and the ambiguous 0° and 180° cases are rejected.

**Units.** Degrees and seconds. Duration defaults from the operator settings when the command does not set one.

**Update.** Evaluated from time. There is no integration of yaw rate. Reported turn rate is the backward difference of the steered heading after the fact (`computedTurnRate`), in degrees per minute.

**Assumptions.** The boat can follow the schedule regardless of speed and regardless of whether the compass is on.

**Limitations.** No heel, no leeway, no rate limit. **Unverified** as a description of Extasy's tacks. Starting the command still checks for an anemometer and a heading instrument. That check is a UI gate, not a term in the equation.

**Validation.** `ManeuverCommandTests`, `TackRegressionTests`, `MeasurementBoundaryTests.aManeuverKeepsTheSameHeadingWhenTheCompassAndGyroAreOff`.

## 8. Position and the current vector

**Purpose.** Move the geographic position from speed over ground and course over ground.

**Kind.** Spherical dead reckoning. The current model is an implemented function that returns zero.

**Inputs.** Water speed in knots, true heading in degrees, `deltaTime` in seconds. `simulatedCurrent` ignores its arguments and returns east and north components of 0 knots.

**Equations.** `simulatedMovement` forms the water vector along the true heading and adds the current. With a zero current, speed over ground equals the water speed and course over ground equals the true heading.

`GPSData.updatePosition` then steps a sphere of radius 6,371,000 m:

```text
distance = SOG * 0.514444 * dt
```

with `SOG` in knots and `distance` in meters. The next latitude and longitude are the spherical destination along the course. The code constant is `0.514444`, not the `0.514444444` in `Utilities/AppConstants.swift`.

**Units.** Knots, degrees, meters, seconds. Latitude and longitude in degrees.

**Update.** One spherical step per physics tick. A new operator coordinate is adopted only when `gpsCoordinateSetpointGeneration` changes. The GPS receiver switch does not stop the step.

**Assumptions.** A sphere is enough. No leeway. No tidal current until a future model writes the east and north components. `ExperimentCurrentProgram` is stored and not read here.

**Limitations.** The radius is not WGS84. **Literature reference required** for a geodetic claim. The knot factor is truncated. **Unverified** against a charted track. The voyage log advances only while the speed log is on. That counter is not `VesselTruth`.

**Validation.** `SimulationPhysicsTests.rmcFixesAdvanceAtPublishedSOG` and `gpsPositionAdvancesWhenTheReceiverIsDisabled`.

## 9. Manual environment redraw

**Purpose.** Vary wind and the other manual environment channels.

**Kind.** Independent uniform replacement samples. Not a turbulence spectrum.

**Inputs.** Each `SimulatedValue` center and offset. The experiment generator when a scenario enabled it.

**Outputs.** `EnvironmentTruth` wind, temperatures, humidity, pressure, and depth. The matching instrument field is nil when that sensor is off.

**Algorithm.** One draw per second, in a fixed order on the physical generator: true wind direction, true wind speed, sea temperature, heading, depth, and manual speed when manual mode is evolving. Air, humidity, and pressure use `measurementRandomGenerator` so they do not shift that order.

```text
x = lower + (upper - lower) * U
U ~ Uniform[0, 1]
```

with the window `center ± offset` clamped to the channel range.

**Units.** Wind direction in degrees. Wind speed in knots. Temperatures in degrees Celsius. Humidity in percent. Pressure in hectopascals. Depth in meters.

**Update.** Replacement at 1 Hz. Between redraws the tick copies truth back onto the instrument fields and then hides disabled sensors.

**Assumptions.** The sample is the new physical value. It is not an error added to a fixed truth.

**Limitations.** Successive samples are independent. There is no gust time scale in manual mode. **Literature reference required** for any meteorological interpretation.

**Validation.** `TruthSeparationTests.seededManualEvolutionIsReproducible`. `MeasurementBoundaryTests.environmentalWindRedrawReplacesTruthAndChangesEstimatedSpeed`.

## 10. Live-weather wind wander

**Purpose.** Move the forecast wind a little between fetches.

**Kind.** A clipped Ornstein–Uhlenbeck step. Heuristic. Unseeded.

**Equation.** `evolveLiveWeatherWindNoise`. For a time step `dt` capped at 4 s,

```text
dx = -theta * x * dt + sigma * sqrt(dt) * Z
Z ~ standard normal from Double.random
```

Speed uses `theta = 0.07` and `sigma = 0.017` kn, then clamps to `[-1.1, 1.1]` kn. Direction uses `theta = 0.06` and `sigma = 0.22` degrees, then clamps to `[-10, 10]` degrees. The forecast plus this offset is committed into `EnvironmentTruth` when live weather is the source.

**Limitations.** The normal draws are not the experiment seed. Two live-weather runs do not repeat. Fetching a forecast still requires the GPS switch, because the request uses vessel position. A forecast already stored is applied without that requirement. **Literature reference required** for the coefficients. **Unverified** as weather.

**Validation.** Live-weather regression tests cover application and failure behavior, not a repeat of the random path.

## 11. Apparent wind

**Purpose.** Derive apparent wind from true wind and boat speed for MWV and related sentences.

**Kind.** Steady kinematic vector sum. Not a new wind measurement.

**Inputs.** Snapshot true wind direction, true wind speed, heading, and boat speed. Heading for the sentence path prefers the resolved true heading.

**Equations.** `NMEA/NMEASimulator+WindCalculations.swift`. Instrument true wind angle:

```text
TWA = normalizeAngle(trueWindDirection - heading)
```

Zero is wind from ahead. Angles through 180° are from starboard. Then, with `TWA` in radians and speeds in knots,

```text
apparent_x = TWS * cos(TWA) + STW
apparent_y = TWS * sin(TWA)
AWS = hypot(apparent_x, apparent_y)
AWA = normalizeAngle(atan2(apparent_y, apparent_x))
```

If snapshot boat speed is nil or zero, apparent wind is not emitted and the true angle is kept. Velocity made good along the heading is `TWS * cos(TWA)`.

**Units.** Knots and degrees. The sentence layer may also print meters per second using `* 0.514444`.

**Update.** Computed when a sentence is built. It is not stored in `EnvironmentTruth`.

**Assumptions.** The boat frame has no heel and no vertical wind. Boat speed is the published log value. A disabled speed log therefore suppresses apparent wind even though `VesselTruth` still has speed through water.

**Limitations.** This is not an anemometer model. **Literature reference required** only if a thesis presents it as more than the standard vector definition. The polar does not use this angle. It uses the unsigned true-wind fold in section 1. `ExperimentSensorModel.apparentWind` evaluates the same pair with speed through water, and `derivedTrueWind` is its inverse. The sentence path itself is unchanged. A disabled speed log suppresses apparent wind in a sentence, because the snapshot boat speed is nil, even though `VesselTruth` still has speed through water.

**Validation.** `NMEASimulatorEngineTests` wind-math cases, including a moving boat and a zero-speed suppression.

## 12. Instrument measurement error

**Purpose.** Simulate the masthead anemometer, the water-speed log, and a true-heading measurement, then calculate true wind from those readings, without moving the boat.

**Kind.** Additive bias and uniform noise on the primary readings, followed by the inverse of section 11. Not part of the tick.

**Inputs.** Water-relative true wind speed and direction, true heading, and speed through water. The physical true heading forms the ideal apparent wind. The measured true heading is used only for calculated true wind direction. Speed over ground is not an input. Magnetic heading and course over ground are not inputs.

**Forward equation.** `ExperimentSensorModel.apparentWind`, matching section 11. A zero speed through water returns the true wind unchanged.

**Inverse equation.** `derivedTrueWind`, using the measured apparent wind and the measured speed through water:

```text
true_x = AWS * cos(AWA) - STW
true_y = AWS * sin(AWA)
TWS = hypot(true_x, true_y)
TWA = normalizeAngle(atan2(true_y, true_x))
TWD = normalizeAngle(measuredHeading + TWA)
measuredHeading = normalizeAngle(physicalHeading + headingBias + headingNoise)
```

A zero measured water speed returns `TWS = AWS` and `TWA = AWA`. A recovered vector of length zero has speed 0 and a nil angle. A nil measured heading leaves that direction nil. True wind speed and true wind angle are not cleared by the missing heading itself. In this truth struct a missing physical heading also removes the boat frame, so the ideal apparent wind is absent as well.

**Error equation.**

```text
measured = ideal + bias + noise
noise ~ Uniform[-A, +A)
```

Heading and the compass use the same sum, then `normalizeAngle`. The positive endpoint is excluded because the unit interval is `[0, 1)`. Each channel has its own `ExperimentRandomGenerator`, seeded from `seed xor (0x9E3779B97F4A7C15 * channel)`. Channels 1–4 are unchanged: apparent wind speed, apparent wind angle, speed through water, and the true-heading instrument. Channel 5 is the magnetic compass.

**Compass equation.** East-positive, each reference applied once:

```text
magnetic = normalizeAngle(trueHeading − variation)
compass = normalizeAngle(magnetic − deviation)
measuredCompass = normalizeAngle(compass + compassBias + compassNoise)
```

The true-heading instrument does not read this compass. A future HDG heading field is the compass card. The deviation and variation fields stay separate. The live HDG heading is still the magnetic course.

**Units.** Knots and degrees. Default bias and amplitude are 0. Nil means missing or rejected. Zero is a real reading.

**Validity.** A negative apparent wind speed or a negative measured water speed is stored and is not inverted. A negative physical water speed, or a missing wind or heading, produces no ideal apparent wind. A missing or non-finite physical heading makes the measured heading nil. Calculated true wind direction is not replaced with the physical heading. Zero degrees remains valid. Values are not clamped.

**Update.** One draw per channel per `measure` call. The caller owns the model.

**Assumptions.** No heel and no vertical wind. The physical true wind is already the water-relative wind. The current model remains zero, so that matches the vessel motion. The true-heading channel observes physical true heading directly. It is not a gyrocompass, a GNSS heading sensor, or an AHRS. The magnetic compass is a separate channel. Variation and deviation are supplied references. The geographic formula and the deviation sine remain the steering-path fields in section 6.

**Limitations.** The engine, the runner, and the sentence builders do not call `measure`. There is no delay, dropout, quantization, or correlation. A moving vessel in still air does not recover a true-wind direction, because the vector is zero. A future gyro or compass model may need a different error. **Literature reference required** before treating the uniform law as a transducer specification. **Unverified** against instrument data sheets.

**Validation.** `ExperimentSensorModelTests` covers recovery on both tacks, the sentence-equation match, bias, independent streams, invalid readings, and an unchanged vessel track.

## 13. Models that are not vessel physics

**Sailing-state bands.** `SailingProfile` labels the point of sail from heading and true wind. The bands are simulator-defined. They do not enter `V_target`. Eligibility for tack and gybe commands uses those labels. **Unverified** as a racing rule.

**Wire faults.** `SentenceScheduler.applyFaultInjection` drops, delays, or corrupts bytes after a sentence exists. Rates use `Double.random` and `Int.random`. Default rates are zero. Faults do not read `VesselTruth`.

**Turn rate.** A diagnostic difference of heading. It does not feed back into the heading schedule.

## Provenance summary

| Model | Source | What a thesis may say today |
|---|---|---|
| Farr table | Stored PDF and `PolarTable` | The program interpolates that table. It does not validate the real Extasy. |
| Pinch, 0.96, offset penalty, retention sine | `SimulationEngine`, `BoatProfile` | Heuristic. Literature reference required. |
| First-order lag | `stepSpeed` | An implemented filter. Not an identified surge model. |
| Dead reckoning | `GPSData.updatePosition` | Spherical, zero current, truncated knot factor. |
| Magnetic variation and deviation | `SimulationEngine` | Cartoon fields. Not a magnetic model. |
| Apparent wind | `NMEASimulator+WindCalculations` and `ExperimentSensorModel` | The sentence builder and the inverse measurement use one water-relative vector pair. Not a masthead calibration. |
| Sensor error | `ExperimentSensorModel` | Bias and uniform noise on apparent wind, the log, a true-heading instrument, and a magnetic compass. Heading error moves calculated true wind direction only. Not on the wire. |
