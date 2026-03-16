# GPIO concepts for WATERBOT

This note explains the Linux GPIO concepts that show up in
[`pkgs/main_compute/src/Gpio.zig`](../pkgs/main_compute/src/Gpio.zig).
It is intended as background for understanding how the rover can control
external hardware such as a motor driver.

## The stack

The current code fits into this chain:

```text
Zig code -> libgpiod -> Linux GPIO driver -> physical GPIO pins
-> motor driver / H-bridge -> motor
```

`Gpio.zig` does not drive a motor directly. It asks Linux to set GPIO output
states, and the external driver board interprets those states.

## What a GPIO chip is

In Linux, `/dev/gpiochipN` is a character device representing one GPIO
controller managed by the kernel.

Important points:

- A GPIO "chip" here does not mean one board pin.
- A GPIO "chip" here also does not necessarily mean one visible physical
  integrated circuit package.
- One `gpiochip` device usually contains many GPIO lines.
- Individual GPIO pins are addressed as line offsets within a chip.

So when code opens `/dev/gpiochip0`, it is opening a controller that owns a
group of GPIO lines. It is not opening one single pin.

In `Gpio.zig`, this is represented by the `Chip` type:

- `Chip.open(...)` opens a device such as `/dev/gpiochip0`
- `Chip.close()` releases it

## What `gpiomem` is

On Raspberry Pi systems, `/dev/gpiomem*` is a separate interface that allows
GPIO register access through memory mapping.

This differs from `gpiochip*` in a few ways:

- `gpiochip*` is the standard Linux GPIO character-device interface.
- `gpiomem*` is Raspberry Pi specific and closer to direct register access.
- Libraries such as `libgpiod` use `gpiochip*`.
- `Gpio.zig` uses `libgpiod`, so it cares about `gpiochip*`, not `gpiomem*`.

## Why the device numbers look sparse

Seeing devices such as:

```text
gpiochip0
gpiochip4
gpiochip10
gpiochip11
gpiochip12
gpiochip13
```

is normal.

The number in `gpiochipN` is a kernel-assigned device index, not:

- the physical header pin number
- the BCM GPIO number
- a guarantee of continuous numbering

Drivers can register GPIO controllers in an order that does not look intuitive
from the outside, so gaps in numbering are expected.

## Why there are fewer `gpiochip` devices than header pins

There is not one `/dev/gpiochip` per header pin.

Instead:

- one GPIO controller exposes many lines
- the board header only exposes some of those lines
- some lines may be internal, reserved, or used for alternate functions

That is why a system can have only a handful of `gpiochip*` devices while the
board exposes many GPIO-capable header pins.

## What a bridge is

In `Gpio.zig`, `Bridge` means one motor-driver channel, typically an H-bridge.

An H-bridge is a circuit that lets software control a DC motor in several
states:

- drive forward
- drive backward
- coast
- brake

That maps directly to the `Direction` enum used by the Zig code.

## What `enable`, `in1`, and `in2` mean

The `BridgePins` struct names the three GPIO lines wired from the Raspberry Pi
to the motor driver:

- `enable`: enables or disables the driver output
- `in1`: first control input
- `in2`: second control input

For a common motor-driver arrangement, the logic is roughly:

```text
enable=0                -> output off / coast
enable=1, in1=1, in2=0  -> drive one direction
enable=1, in1=0, in2=1  -> drive opposite direction
enable=1, in1=1, in2=1  -> brake
```

The exact truth table depends on the motor-driver hardware, but this is the
behavior assumed by `Gpio.zig`.

## When a pin actually turns on or off

The code produces output levels in two stages.

First, during `Bridge.init(...)`, the program:

- chooses three line offsets: `enable`, `in1`, and `in2`
- configures those lines as outputs
- sets their initial values to inactive
- requests ownership of those lines from the kernel

That initial output state comes from `inactiveTriplet()`, which builds:

```text
[INACTIVE, INACTIVE, INACTIVE]
```

Second, later on, `Bridge.set(direction)` converts a high-level direction into
three output values and writes them to the kernel with
`gpiod_line_request_set_values(...)`.

That call is the moment where the requested logical states are pushed out to
the physical pins.

Examples:

- `forward` becomes `[ACTIVE, ACTIVE, INACTIVE]`
- `backward` becomes `[ACTIVE, INACTIVE, ACTIVE]`
- `coast` becomes `[INACTIVE, INACTIVE, INACTIVE]`
- `brake` becomes `[ACTIVE, ACTIVE, ACTIVE]`

The ordering is always:

```text
[enable, in1, in2]
```

## Active vs. high

The file uses `ACTIVE` and `INACTIVE`, which come from `libgpiod`.

In this code, the lines are not configured as `active_low`, so `ACTIVE`
effectively means the asserted output level and `INACTIVE` means the
deasserted level. In a typical setup, that corresponds to:

- `ACTIVE` -> electrical high
- `INACTIVE` -> electrical low

It is better to think in terms of asserted and deasserted states than to assume
all hardware always uses high for "on".

## Useful inspection commands

If `libgpiod` tools are installed on the Raspberry Pi, these commands help show
what GPIO controllers and lines Linux knows about:

```bash
gpiodetect
gpioinfo
gpioinfo gpiochip0
```

They are useful for answering:

- how many lines each GPIO controller exposes
- which lines are already in use
- whether line names match board documentation
