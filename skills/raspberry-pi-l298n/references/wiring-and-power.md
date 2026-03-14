# Wiring and power for Raspberry Pi + L298N

## Board model to assume

Assume the common L298N breakout with:

- `OUT1`, `OUT2` for motor A
- `OUT3`, `OUT4` for motor B
- `ENA`, `IN1`, `IN2` controlling bridge A
- `ENB`, `IN3`, `IN4` controlling bridge B
- `+12V` or `VS`, `GND`, and `5V` power terminals
- a `5V-EN` or similar jumper for the onboard 5 V regulator
- jumpers on `ENA` and `ENB` on some boards

Do not assume every clone labels the pins identically. If the user provides a
photo or product page, align to that board.

## Core electrical facts

- DIYables markets this module as `5 V to 35 V` motor supply and `2 A per
  channel`, with logic listed as `5 V` and `3.3 V` compatibility only `with
  level shifter`.
- ST documents the L298 chip itself as accepting standard TTL logic levels.
- The breakout usually includes a 78M05-style regulator controlled by a jumper.
- The module has a significant voltage drop across the H-bridge. Expect the
  motor to see meaningfully less than the supply voltage.

## Safe default wiring for one DC motor

Use bridge A unless the user has a reason to prefer bridge B.

- Motor leads -> `OUT1`, `OUT2`
- External motor supply positive -> `+12V` or `VS`
- External motor supply ground -> `GND`
- Raspberry Pi ground -> same `GND`
- Raspberry Pi PWM-capable GPIO -> `ENA`
- Raspberry Pi GPIO -> `IN1`
- Raspberry Pi GPIO -> `IN2`

If the board has an `ENA` jumper installed, remove it when variable speed
control is needed. Leaving it installed ties enable high, which is fine for
on/off control but not for Pi-driven PWM on that channel.

## Two-DC-motor wiring

Bridge A:

- `ENA`, `IN1`, `IN2`, `OUT1`, `OUT2`

Bridge B:

- `ENB`, `IN3`, `IN4`, `OUT3`, `OUT4`

Give each bridge its own enable PWM pin if the user wants independent speed
control.

## Stepper wiring

The common L298N module can drive a 4-wire bipolar stepper by using both
bridges:

- Coil A -> `OUT1`, `OUT2`
- Coil B -> `OUT3`, `OUT4`
- `IN1` and `IN2` drive coil A polarity
- `IN3` and `IN4` drive coil B polarity

This is workable for small steppers but is not equivalent to a modern current-
regulated stepper driver. Be explicit about that tradeoff.

## 5 V jumper rules

Treat the `5V` terminal according to the regulator jumper state:

- Motor supply `<= 12 V`, jumper fitted:
  the onboard regulator usually powers the module logic, and the `5V` pin is
  typically an output on common boards.
- Motor supply `> 12 V`, jumper removed:
  many common boards require an external regulated `5V` input on the `5V` pin
  to power logic.

Because clone boards vary, do not instruct the user to connect Raspberry Pi `5V`
to the module unless the board behavior is confirmed. The safest common advice
is:

- always share `GND`
- keep Pi GPIO on control inputs only
- confirm jumper behavior before using the board's `5V` pin in either direction

## Raspberry Pi logic-level guidance

Use a conservative stance:

- The L298 chip family uses TTL-like logic thresholds.
- Many users drive `INx` and `ENx` directly from 3.3 V Raspberry Pi GPIO and it
  works.
- The DIYables page explicitly phrases 3.3 V compatibility as requiring a level
  shifter.

So the skill should say:

- direct 3.3 V GPIO often works on L298N modules in practice
- if the user wants maximum margin or the board vendor requires it, add a level
  shifter or transistor interface
- never exceed Raspberry Pi GPIO limits

## Bring-up checklist

1. Disconnect motors before first continuity and jumper checks.
2. Confirm `GND` is common between Pi and driver.
3. Confirm motor supply polarity.
4. Confirm `ENA` and `ENB` jumper choices match whether PWM will be used.
5. Power the driver before commanding motion.
6. Start with low PWM duty and short test bursts.
7. Check regulator and heatsink temperature during the first loaded run.

## Sources

- DIYables product page: https://diyables.io/products/l298n-motor-driver-module
- ST product page: https://www.st.com/en/product/L298
- ST datasheet PDF: https://www.st.com/resource/en/datasheet/l298.pdf
- Common module jumper behavior reference:
  https://lastminuteengineers.com/l298n-dc-stepper-driver-arduino-tutorial/
