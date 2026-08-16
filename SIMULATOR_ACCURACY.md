# Simulator Accuracy vs Real Hardware

## Real NMEA 0183 hardware constraints

- **Baud rate**: 4800 baud = ~480 chars/sec = 8–14 sentences/sec physical maximum
- **GPS sentences**: 1 Hz (some units support 5/10 Hz but require explicit config)
- **Compass (fluxgate)**: 1–10 Hz for HDG; most B&G Triton 2 = 10 Hz
- **Depth**: 1 Hz
- **Wind (anemometer)**: 1 Hz
- **Rate of turn**: 10 Hz (computed from gyro)
- **Multi-talker**: A typical boat has GP (GPS), HC (compass), SD (depth), II (instruments) on separate buses, sometimes multiplexed by a Yacht Devices or B&G gateway.

## Using Realistic Mode for profiling

Always run the simulator in `Realistic` rate mode when profiling ExtasyCompleteNavigation with Instruments. Custom mode can be used to stress-test the parser, but Energy reports taken from custom-rate sessions overstate CPU by 3–5×.

## Known differences from real hardware

- Serial port byte-timing jitter (~1–5 ms between characters) is not simulated
- NMEA talker clock drift (each instrument has its own oscillator) is not simulated
- Sentence interleaving from a hardware multiplexer is approximated, not exact

## Cross-track error (RMB / XTE) precision

RMB and XTE emit XTE with **2 decimal places** (NM), ~19 m resolution — typical of chartplotters / race instruments. One decimal (~185 m steps) looked too coarse for realistic demo profiling against Extasy.
