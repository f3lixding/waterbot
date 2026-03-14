---
name: raspberry-pi-l298n
description: Help wire a Raspberry Pi to an L298N motor driver module and write code to control one or two brushed DC motors, or a 4-wire stepper using the common breakout board. Use when Codex needs to map GPIO pins to ENA/ENB and IN1-IN4, reason about the 5V regulator jumper and shared ground, choose a Linux GPIO interface such as libgpiod, or generate C, Zig, or troubleshooting guidance for an L298N-based setup.
---

# Raspberry Pi L298N

## Overview

Use this skill to turn an L298N module and Raspberry Pi into a concrete wiring plan
and working control code. Default to C and Zig via `libgpiod`, not Python, unless
the user explicitly asks for another stack. Prefer conservative wiring guidance
because common L298N breakout boards vary slightly and the Raspberry Pi is 3.3 V
logic only.

## Workflow

1. Identify the motor type.
2. Load [wiring-and-power.md](./references/wiring-and-power.md) before giving any
   connection advice.
3. Load [c-zig-control-patterns.md](./references/c-zig-control-patterns.md)
   before writing Raspberry Pi code.
4. Keep motor power and Raspberry Pi power paths separate unless the user has a
   clearly safe design.
5. Call out the L298N's voltage drop and heat dissipation limits when they affect
   expected torque or speed.

## What to determine first

- How many motors are being controlled: one DC motor, two DC motors, or one
  4-wire stepper.
- Motor supply voltage and stall current.
- Whether the module's `5V-EN` regulator jumper is installed.
- Which GPIO interface is actually available on the target Pi or NixOS image.
- Whether the user wants simple direction control or variable speed with PWM.

## Preferred control patterns

- For one DC motor on one bridge, prefer a single `libgpiod` line request over
  `ENA`, `IN1`, and `IN2`.
- For two DC motors, either request all six lines together or use one request
  per bridge if the separation is clearer in the codebase.
- For modules with ENA/ENB jumpers left installed, note that speed control is
  disabled and the motor will run at full duty when enabled.
- For a 4-wire stepper on this module, write an explicit coil sequence against
  `IN1`-`IN4`; do not pretend the board is a chopper stepper driver.
- For Zig, prefer `@cImport` of `gpiod.h` over wrapping shell tools.
- Use Python only as a fallback when the user explicitly wants it or the project
  already depends on it.

## Safety and correctness rules

- Always require a common ground between the Raspberry Pi and the L298N module.
- Do not tell the user to power a motor from Raspberry Pi GPIO or from a Pi 5 V pin.
- Treat the L298N breakout's `5V` pin carefully:
  keep the explanation aligned with jumper state and motor supply voltage.
- If motor supply is over 12 V, explicitly tell the user to remove the onboard
  regulator jumper and provide logic 5 V separately if that board revision
  requires it.
- Note that the L298 family is old and inefficient; warn about the roughly 2 V
  output drop and likely heating under load.
- Do not claim the module is natively 3.3 V-logic safe in every configuration.
  ST documents TTL-compatible inputs on the chip, while the vendor page phrases
  3.3 V compatibility more cautiously. Present that nuance.
- Do not assume `gpiochip0` or raw offsets blindly on every Raspberry Pi image.
  Confirm the chip and line mapping with `gpiodetect`, `gpioinfo`, or equivalent
  before hard-coding offsets.
- Do not present `libgpiod` as a full PWM solution. It is suitable for GPIO line
  control; sustained speed control may need a hardware PWM path or acceptance of
  software-timing limits.

## Response shape

- Start with the exact wiring map using physical header pin numbers and the
  corresponding GPIO line identifiers needed by the chosen code path.
- Separate `motor power`, `logic power`, and `GPIO control` sections.
- Include one runnable code sample in the user's primary language, ideally Zig
  or C for this project.
- Include a bring-up checklist:
  verify shared ground, verify jumper state, test one motor at low duty, then
  expand.
