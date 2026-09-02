# GD32F350 Hardware Test Report

Date: 2026-09-03

## Summary

The GD32F350 port builds successfully and its core motor-control path works on
real hardware. DShot300, DShot600, bidirectional eRPM telemetry, startup
arming safety, repeated starts/stops, signal-loss shutdown, and DShot beacon
command 1 were exercised.

Two functional failures were found:

1. Correctly timed DShot frames with an invalid CRC keep the last valid
   throttle active indefinitely instead of entering signal-loss failsafe.
2. F350 ADC processing is not periodically executed. Extended telemetry
   reports zero temperature, voltage, and current, and ADC-dependent
   protections cannot operate correctly.

Three additional source-level risks were found: erased EEPROM can produce an
integer divide by zero during startup, high-side GPIO output options are
applied to GPIOB instead of the target-defined ports, and the filename linker
region overlaps the last 32 bytes of the declared application flash region.

This is a comprehensive test of the features reachable with the available
single-wire DShot setup. Features requiring a UART connection, oscilloscope,
controlled mechanical load, temperature chamber, programmable supply, or
configuration programmer are explicitly marked untested.

## Test Setup

| Item | Configuration |
|---|---|
| ESC MCU | GD32F350x8, Cortex-M4, 64 KiB flash, 8 KiB RAM |
| Firmware | AM32 2.21 `REF_F350` standalone hardware-test image |
| Motor | Unloaded BLDC motor |
| Supply | Current limit set to 1 A |
| DShot host | Seeed XIAO RP2350, D0 / GPIO26 |
| Tester software | MIT `pio-dshot` adaptation in `dshot-tester/` |
| Signal wiring | Common ground, one pull-up to 3.3 V, no pull-down |
| DShot rates | DShot300 and DShot600 |
| Debug access | No SWD probe connected during this test session |
| Missing instrumentation | No optical tachometer, gate-output scope, PB6 UART capture, controlled load, or independent voltage/current/temperature measurement |

The hardware-in-loop tests used the previously flashed standalone image at
`0x08000000`. The clean repository build below uses the production bootloader
layout at `0x08001000`. They are built from the same F350 firmware sources,
but the production-layout artifact was not reflashed during this session.

## Tester Validation

The original custom tester used separate transmit and receive PIO state
machines and corrupted subsequent DShot frames when it changed GPIO direction.
It was replaced with an adaptation of:

<https://github.com/simonwunderlich/pio-dshot>

The adaptation preserves the upstream MIT license and uses one PIO state
machine for inverted transmission, immediate line release, response timeout,
sampling, differential decode, GCR decode, and checksum validation.

RP2350/F350-specific changes:

- Calculate the PIO divider from `clock_get_hz(clk_sys)` instead of assuming
  the RP2040's 133 MHz system clock.
- Release the line immediately after transmission rather than continuing to
  drive it during the turnaround interval.
- Sample each F350 telemetry cell every 34 PIO cycles. F350 TIMER2 produces a
  cell in approximately `101 / 72 MHz = 1.403 us`; 34 cycles at the DShot600
  PIO clock is approximately 1.417 us.
- Add controlled DShot300/600 switching, frame pause, invalid-CRC injection,
  telemetry statistics, beacon command 1, and extended telemetry controls.

After these corrections, stopped-motor telemetry decoded as zero eRPM and
running telemetry tracked throttle changes consistently.

## Build Verification

### Commands

The repository-pinned xPack toolchain was not installed. The clean build used
the installed Arm GNU Toolchain 14.2.1 and the known GCC 14 array-bounds
compatibility suppression:

```sh
make clean
make ARM_SDK_PREFIX=arm-none-eabi- \
  CFLAGS_COMMON='$(CFLAGS_BASE) -Wall -Wundef -Wextra -Werror \
  -Wno-unused-parameter -Wno-stringop-truncation -Wno-array-bounds' \
  REF_F350
make ARM_SDK_PREFIX=arm-none-eabi- \
  CFLAGS_COMMON='$(CFLAGS_BASE) -Wall -Wundef -Wextra -Werror \
  -Wno-unused-parameter -Wno-stringop-truncation -Wno-array-bounds' \
  f350
```

### Results

| Check | Result |
|---|---|
| `make targets` discovers `REF_F350` | Pass |
| Clean `REF_F350` compile and link | Pass |
| Aggregate `make f350` | Pass; `REF_F350` is the only F350 target |
| Compiler warnings treated as errors | Pass with GCC 14 compatibility suppression |
| ELF architecture | Pass: ELF32 little-endian Arm, EABI5, Cortex-M4 soft-float |
| Vector address | Pass: `.vectors` at `0x08001000` |
| Initial stack pointer | Pass: `0x20001468`, inside 8 KiB RAM |
| Reset vector | Pass: `0x08005D2D`, Thumb address inside application flash |
| Filename section | Pass: `REF_F350` at `0x0800F7E0`, 32 bytes |
| EEPROM reservation | Pass: starts at `0x0800F800`, size 2 KiB |
| Tester build | Pass: RP2350 UF2 built with Ninja |
| Whitespace/error check | Pass: `git diff --check` |

Newlib emitted expected linker notices for unimplemented `_read`, `_write`,
`_close`, and `_lseek` stubs. These are not used by the firmware runtime.

### Memory Use

| Region | Used | Capacity | Utilization |
|---|---:|---:|---:|
| Application flash | 25,984 bytes | 58 KiB | 43.75% |
| RAM | 5,224 bytes | 8 KiB | 63.77% |
| Filename | 32 bytes | 32 bytes | 100% |
| EEPROM | 0 bytes linked | 2 KiB reserved | 0% linked |

Generated artifacts:

- `obj/AM32_REF_F350_2.21.elf`: 559,984 bytes including debug information
- `obj/AM32_REF_F350_2.21.bin`: 59,392 bytes including the gap to filename
- `obj/AM32_REF_F350_2.21.hex`: 73,260 bytes

## Hardware Test Results

### Boot And Arming

| Test | Result | Evidence |
|---|---|---|
| Boot and startup tones | Pass | Firmware reached `main()` and produced motor startup tones in prior standalone-image validation |
| Nonzero throttle present before power-on | Pass | Tester continuously sent throttle 100 before ESC power-on; motor remained stopped for more than three seconds |
| Zero-throttle arming after rejected nonzero boot | Pass | Three seconds of throttle zero followed by throttle 100 produced 5,281 eRPM |
| Repeated arm/run/stop behavior | Pass | Three cycles produced 5,266, 5,311, and 5,341 eRPM; each zero command returned telemetry to zero |

### DShot600 Throttle Boundary

Each point was held for 2.5 seconds. The motor was unloaded.

| DShot value | Final eRPM | Result |
|---:|---:|---|
| 47 | 0 | Pass: reserved command range did not spin motor |
| 48 | 0 | Pass: minimum throttle value remained stopped on this setup |
| 75 | 2,858 | Pass |
| 100 | 5,419 | Pass |
| 150 | 16,059 | Pass |
| 200 | 26,041 | Pass |
| 0 | 0 | Pass: disarm/stop |

Values above 200 were not tested because of the 1 A supply limit and lack of a
mechanical safety fixture. Parser value 2047 and out-of-range clamping were
therefore not applied to the powered ESC.

### Low-Throttle Startup Boundary

The motor was returned to zero for 1.5 seconds before each attempt.

| DShot value | Peak eRPM | Final eRPM | Result |
|---:|---:|---:|---|
| 48 | 0 | 0 | Did not start |
| 50 | 4,758 | 2,733 | Started |
| 55 | 5,733 | 2,806 | Started |
| 60 | 6,487 | 2,929 | Started |
| 65 | 5,841 | 2,790 | Started |
| 70 | 6,510 | 2,781 | Started |
| 75 | 5,387 | 2,832 | Started |

For this unloaded motor and current settings, the observed startup boundary is
between DShot values 48 and 50.

### Dynamic And Endurance Tests

| Test | Result | Evidence |
|---|---|---|
| Eight rapid transitions between throttle 75 and 200 | Pass | Every interval retained valid telemetry; low points were 2,087-2,893 eRPM and high points were 25,252-25,684 eRPM |
| DShot600 30-second run at throttle 100 | Pass | 28,553 valid responses, 7,559 GCR rejects, no timeout or checksum failures |
| Steady speed during 30-second run | Pass | 5,252-5,387 eRPM after the first five seconds |
| True signal loss while running | Pass | Motor physically stopped during a two-second frame pause; firmware recovered after output resumed at zero |
| Correctly timed frames with invalid CRC | **Fail** | Motor remained running at 5,296 eRPM after 2.5 seconds of exclusively invalid-CRC frames |

### DShot300

| Test | Result | Evidence |
|---|---|---|
| Idle/zero telemetry | Pass | 2,578 valid zero-eRPM responses, 1,142 acquisition timeouts, 658 GCR rejects |
| Throttle 100 | Pass | 5,281 eRPM; 3,160 valid responses, 74 GCR rejects, no timeouts/CRC failures |
| Speed change while running | Pass in tester | Tester refused the change until throttle was zero |
| Live DShot300 to DShot600 change at zero | Requires reset | AM32 lost telemetry until a signal-loss reset and new rate acquisition |

DShot rate should be treated as fixed for an armed session. A zero throttle
command alone does not guarantee that AM32 will reacquire a different rate.

### Bidirectional Telemetry Quality

| Scenario | Valid | Rejected/timeout | Valid rate |
|---|---:|---:|---:|
| DShot600 idle, five seconds | 4,657 | 1,293 | 78.3% |
| DShot600 throttle 100, 30 seconds | 28,553 | 7,559 | 79.1% |
| DShot300 idle | 2,578 | 1,800 | 58.9% |
| DShot300 throttle 100 | 3,160 | 74 | 97.7% |

No checksum failures occurred in these corrected-timing samples. Most rejected
frames were invalid GCR symbols, indicating remaining phase/timing sensitivity
in the tester. The successfully decoded values were stable and monotonic, but
absolute eRPM accuracy was not checked against an independent tachometer.

### DShot Commands And Extended Telemetry

| Test | Result | Evidence |
|---|---|---|
| Beacon command 1 while stopped | Pass | Beacon was physically audible |
| EDT enable/disable commands 13/14 | Pass | Tester received interleaved EDT sensor frame types |
| EDT eRPM | Pass | Valid and monotonic with throttle |
| EDT temperature | **Fail** | Reported exactly 0 C stopped and running |
| EDT voltage | **Fail** | Reported exactly 0 V with the ESC powered |
| EDT current | **Fail/inconclusive electrically** | Reported 0 A while running; voltage and temperature failures plus source inspection confirm the ADC update path is broken |

## Findings

### F1: Invalid-CRC Traffic Defeats Signal-Loss Shutdown

Severity: Critical

Status: Reproduced on hardware

`computeDshotDMA()` resets `signaltimeout` as soon as the captured frame length
is plausible, before validating its CRC:

- `Src/dshot.c:76-77`: frame timing resets `signaltimeout`.
- `Src/dshot.c:98-104`: CRC polarity adjustment and validation happen later.
- `Src/dshot.c:235-237`: bad CRC only increments `dshot_badcounts` and clears
  programming mode.
- `Src/main.c:1977-2003`: shutdown/reset depends on `signaltimeout` increasing.

As a result, an ongoing stream of correctly timed corrupt frames prevents the
failsafe while the last valid throttle remains active. The motor was still
running at 5,296 eRPM after 2.5 seconds of bad frames. Complete frame loss did
stop the motor, so the failure is specifically the invalid-frame path.

Recommended correction: reset `signaltimeout` only after CRC validation, or
add a bounded consecutive-bad-frame shutdown independent of frame timing.

### F2: F350 ADC Data Is Not Periodically Processed

Severity: High

Status: Reproduced through EDT and confirmed by source inspection

`Mcu/f350/Src/ADC.c:76` disables continuous conversion and
`Mcu/f350/Src/ADC.c:105` starts only the initial scan. Periodic ADC processing
in `Src/main.c:2112-2150` has branches for STM32, GD32E23, Artery, NXP, and
WCH, but no GD32F350 branch. Therefore `ADC_DMA_Callback()` is not called and
the next conversion is not triggered for F350.

Observed EDT values were 0 C, 0 V, and 0 A both stopped and running.

Affected behavior includes:

- Serial/extended temperature, voltage, and current telemetry
- Low-voltage cutoff
- Current limiting and consumption accumulation
- Temperature protection/derating

Recommended correction: add an F350 periodic branch equivalent to the E230
path, including `ADC_DMA_Callback()`, temperature conversion, and
`adc_software_trigger_enable(ADC_REGULAR_CHANNEL)`.

### F3: Erased EEPROM Can Cause Integer Divide By Zero

Severity: High

Status: Source-level finding; destructive blank-EEPROM HIL test not run

`loadEEpromSettings()` reads raw flash before version migration. For erased
flash, `eepromBuffer.motor_poles` is `0xFF`. At `Src/main.c:792-793`,
`32 / motor_poles` evaluates to zero and is then used as the divisor of two
more integer divisions. A zero `motor_poles` value is also invalid.

Version fields are updated only after `loadEEpromSettings()` returns at
`Src/main.c:1797-1802`, so version migration does not protect this calculation.

Recommended correction: validate `motor_poles` and all divisor-producing
settings before use, and load a complete known-good default EEPROM structure
when the version/header is erased or invalid.

### F4: High-Side GPIO Output Options Use The Wrong Port

Severity: Medium

Status: Source-level finding; motor operation works from reset defaults

`Mcu/f350/Src/peripherals.c:191-204` configures the target-defined high-side
pins' modes correctly, but calls `gpio_output_options_set(GPIOB, ...)` three
times. `REF_F350` high-side outputs are PA10, PA9, and PA8, so these calls
should use `PHASE_A_GPIO_PORT_HIGH`, `PHASE_B_GPIO_PORT_HIGH`, and
`PHASE_C_GPIO_PORT_HIGH`.

The motor runs, but output type/speed configuration is applied to unrelated
GPIOB bits. Gate edge rate and electrical behavior require scope verification
after correction.

### F5: Filename Region Shares The End Of Application Flash

Severity: Low

Status: Source-level finding; current image has ample margin

The application `FLASH` region extends through `0x0800F7FF`, while
`.file_name` is independently placed at `0x0800F7E0-0x0800F7FF`. A future
near-full image could overlap the filename instead of receiving a clean linker
capacity failure. The current application ends near `0x08007580`, so this does
not affect the tested build.

Recommended correction: end the normal `FLASH` region at `0x0800F7E0` and
keep the filename as a separate 32-byte region.

## Feature Coverage And Gaps

| Feature | Status | Reason/notes |
|---|---|---|
| MCU boot, clocks, RAM, flash, vectoring | Pass | Boot and motor operation; production image structure checked |
| Six-step startup and BEMF commutation | Pass at functional level | Reliable unloaded starts and speed transitions |
| DShot300 and DShot600 | Pass | DShot rate changes require reset/reacquisition |
| DShot arming safety | Pass | Nonzero-at-boot rejected; zero sequence required |
| Complete signal-loss failsafe | Pass | Physical stop confirmed |
| Invalid-frame failsafe | Fail | F1 |
| Bidirectional eRPM | Pass with tester error rate | No independent tachometer |
| DShot beacon/audio | Pass | Command 1 physically confirmed |
| EDT sensor telemetry | Fail | F2 |
| Voltage/current/temperature protection | Not safely testable and likely nonfunctional | Depends on failed ADC path |
| Servo PWM input and stick calibration | Not tested | Requires a PWM generator/wiring change |
| PB6 KISS serial telemetry and ESC-info packet | Not tested | Requires 3.3 V UART capture on PB6 |
| Direction reversal and bidirectional/3D mode | Not tested | Requires controlled mechanical setup and direction instrumentation |
| Brake/coast/drag/active braking modes | Not tested | Regeneration requires suitable supply/load fixture |
| Stuck-rotor and stall protection | Not tested | Unsafe without a restrained load and independent current measurement |
| Desync recovery under load | Not tested | Requires controlled dynamometer/load |
| EEPROM programming and persistence | Not tested | Requires configuration protocol host; blank-flash test is destructive |
| Sine startup and configurable PWM frequency | Not tested | Requires settings programmer and oscilloscope |
| Complementary PWM/dead time/gate sequencing | Functional motor test only | Exact waveform requires a differential oscilloscope |
| Production bootloader-to-app jump | Image checked only | HIL used standalone application layout |
| SWD fault/state inspection | Not tested this session | Debug probe was not connected |

REF_F350 does not enable LED strip, discrete RGB LED, Hall sensor, ADC throttle,
RPM pulse output, CRSF, DroneCAN, brushed, gimbal, fixed-duty, or fixed-speed
features. They are not applicable to this target configuration.

## Recommended Next Work

1. Fix F1 before considering the port safe for powered operation.
2. Add the missing F350 periodic ADC path and repeat EDT plus independent
   voltage/current/temperature measurements.
3. Validate/sanitize EEPROM before any setting-derived division, then test a
   fully erased EEPROM page on hardware.
4. Correct high-side GPIO port arguments and inspect all six gate signals and
   dead time with a scope.
5. Reflash the production bootloader-layout image and verify the real
   bootloader jump, application update, and EEPROM preservation.
6. Connect PB6 to a UART receiver and validate KISS telemetry and ESC-info.
7. Use a tachometer and controlled load to quantify eRPM accuracy, commutation
   stability, braking, reversal lockout, stall protection, and desync recovery.
