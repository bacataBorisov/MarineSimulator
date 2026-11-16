# Simulator Accuracy vs Real Hardware

## Real NMEA 0183 hardware constraints

- **Baud rate**: 4800 baud = ~480 bytes/s (8–14 sentences/s physical maximum); 38400 baud (HS-NMEA) = ~3,840 bytes/s
- **GPS sentences**: 1 Hz (some units support 5/10 Hz but require explicit config)
- **Compass (fluxgate)**: 1–10 Hz for HDG; most B&G Triton 2 = 10 Hz
- **Depth**: 1 Hz
- **Wind (anemometer)**: 1 Hz
- **Rate of turn**: 10 Hz (computed from gyro)
- **Multi-talker**: A typical boat has GP (GPS), HC (compass), SD (depth), II (instruments) on separate buses, sometimes multiplexed by a Yacht Devices or B&G gateway.

## Implemented Hardware-Realism Controls

- **Realistic rate mode (`Simulation → Sentence Update Rates`)**: Hardware-accurate per-sentence intervals and talker IDs (`HardwareProfile`). Always run in `Realistic` rate mode when profiling `ExtasyCompleteNavigation` with Instruments; Custom mode overstates CPU by 3–5×.
- **Optional Bus Speed limiter (`Unlimited` / `4800 baud` / `38400 baud`)**: `SentenceScheduler.paceSentencesByBaudRate` enforces an 8N1 byte budget per 50 ms tick with a ~2 s backlog buffer and drops overflow sentences (logging a throttled warning to Transport History).
- **Optional TCP Stream Fragmentation (`Advanced Simulation Controls`)**: `TCPClient` splits outgoing TCP sentences into multiple small writes (6 ms apart) to stress-test receiver stream reassembly across packet boundaries.

## Known differences from real hardware

- UART byte-level timing jitter (1–5 ms between individual characters) is not simulated on UDP datagrams
- Independent NMEA talker oscillator clock drift (each instrument on its own quartz clock) is not simulated
- Multiplexer sentence interleaving order is approximated on 50 ms ticks

## Cross-track error (RMB / XTE) precision

RMB and XTE emit XTE with **2 decimal places** (NM), ~19 m resolution — typical of chartplotters / race instruments. One decimal (~185 m steps) looked too coarse for realistic demo profiling against Extasy.
