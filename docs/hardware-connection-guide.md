# Hardware connection guide

This document describes a practical first wiring setup for:

- Raspberry Pi 5
- L298N dual H-bridge motor driver
- 2WD chassis with two DC gear motors

It is intended as a bring-up guide for Phase 1 driving.

## What this wiring does

The Raspberry Pi uses GPIO pins to send control signals to the L298N.
The L298N switches motor power from the battery to the two DC motors.

The control chain is:

```text
Raspberry Pi GPIO -> L298N motor driver -> DC motors
```

Power is separate:

```text
Battery -> L298N motor power
Pi power supply -> Raspberry Pi
```

The Pi and motor driver still need a shared ground.

## Safety notes

- Do not power the motors from the Raspberry Pi.
- Do not connect motor supply voltage directly to any Pi GPIO pin.
- Make sure Raspberry Pi ground and L298N ground are connected together.
- Double-check polarity before powering the board.
- Power off before moving wires.

## Parts involved

- Raspberry Pi 5
- L298N motor driver module
- Two DC motors
- Battery pack for the motors
- Separate power supply for the Raspberry Pi
- Jumper wires

## GPIO naming note

This guide uses BCM GPIO names such as `GPIO18` and `GPIO23`.

If you prefer physical header pin numbers, use a Raspberry Pi pinout reference
while wiring. The software side should continue to think in terms of BCM GPIO
numbers or the corresponding `gpiochip` line offsets.

## Recommended control wiring

This wiring gives software control over both direction and enable lines.

### Motor A

- Pi `GPIO18` -> L298N `ENA`
- Pi `GPIO23` -> L298N `IN1`
- Pi `GPIO24` -> L298N `IN2`

### Motor B

- Pi `GPIO13` -> L298N `ENB`
- Pi `GPIO27` -> L298N `IN3`
- Pi `GPIO22` -> L298N `IN4`

### Ground

- Pi `GND` -> L298N `GND`

The common ground is required so the Pi's control signals have the same voltage
reference as the motor driver.

## Motor wiring

Connect the two motors to the output screw terminals on the L298N:

- Right motor -> `OUT1` and `OUT2`
- Left motor -> `OUT3` and `OUT4`

If a motor spins in the opposite direction from what you expect, swap that
motor's two wires at the `OUTx` terminals.

## Power wiring

Use the battery to power the motor side of the L298N:

- Battery positive -> L298N `12V` or `VS`
- Battery negative -> L298N `GND`

Use a separate supply for the Raspberry Pi:

- Pi USB-C power input -> proper Pi power adapter or regulated 5 V source

Also connect:

- Pi `GND` -> L298N `GND`

That means battery ground, L298N ground, and Pi ground all meet at the driver
board ground.

## `ENA` and `ENB` jumpers

Many L298N modules ship with jumpers installed on `ENA` and `ENB`.

- If the jumper is installed, that motor channel is always enabled.
- If you want software control of enable and speed, remove the jumper and wire
  `ENA` or `ENB` to Raspberry Pi GPIO.

For the setup in this document, remove both enable jumpers and use the GPIO
connections listed above.

## Logic model

For each motor channel, the usual control logic is:

```text
enable=0                -> motor off / coast
enable=1, in1=1, in2=0  -> one direction
enable=1, in1=0, in2=1  -> opposite direction
enable=1, in1=1, in2=1  -> brake
```

This matches the model used in `pkgs/main_compute/src/Gpio.zig`.

## Suggested motor mapping in software

The current `Gpio.zig` abstraction models one bridge at a time using:

- `enable`
- `in1`
- `in2`

That maps cleanly to one L298N channel.

Example:

- Motor A bridge pins: `ENA`, `IN1`, `IN2`
- Motor B bridge pins: `ENB`, `IN3`, `IN4`

## First power-on checklist

Before applying power:

- confirm Pi `GND` is connected to L298N `GND`
- confirm battery positive is connected to `12V` or `VS`
- confirm battery negative is connected to `GND`
- confirm no motor power wire touches any Pi GPIO pin
- confirm `ENA` and `ENB` jumpers are removed if software controls enable
- confirm motors are connected only to `OUT1/OUT2` and `OUT3/OUT4`

First test sequence:

- power the Pi from its normal power supply
- power the L298N from the motor battery
- command one motor forward briefly
- command stop
- command reverse briefly
- repeat for the second motor

If the wheel direction is reversed, swap that motor's output wires.

## Recommended references

- Raspberry Pi GPIO reference: <https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#gpio-and-the-40-pin-header>
- Raspberry Pi pinout reference: <https://pinout.xyz/>
- SunFounder L298N module notes: <https://docs.sunfounder.com/projects/3in1-kit/en/latest/components/component_l298n_module.html>
- SunFounder car wiring examples: <https://docs.sunfounder.com/projects/3in1-kit/en/latest/car_project/car_move_by_code.html>
- ST L298 product page: <https://www.st.com/content/st_com/en/products/motor-drivers/brushed-dc-motor-drivers/l298.html>
