# C and Zig control patterns for Raspberry Pi + L298N

## Default software stack

Prefer `libgpiod` for Raspberry Pi GPIO access from C and Zig. Raspberry Pi's
current guidance recommends the standard Linux `libgpiod` path rather than old
sysfs GPIO or direct register access, especially on Raspberry Pi 5-class
hardware.

Use Python only if the user explicitly asks for it or the surrounding project
already uses it.

## Do not assume the chip or offsets

Raspberry Pi documents that a system can expose multiple `gpiochip` devices, and
that GPIO offsets are internal to a chip rather than a universal GPIO number.
On Raspberry Pi 5, the user-facing GPIOs have been aligned back to `gpiochip0`
on current software stacks, but the safe workflow is still to inspect the target
system first.

Before hard-coding anything, inspect the target:

```sh
gpiodetect
gpioinfo gpiochip0
```

If a line name is exposed and stable on the target image, prefer resolving by
name. Otherwise use explicit chip path plus offset.

## `libgpiod` model to use

Use the v2 core API pattern:

1. `gpiod_chip_open`
2. `gpiod_line_settings_new`
3. `gpiod_line_settings_set_direction`
4. `gpiod_line_config_new`
5. `gpiod_line_config_add_line_settings`
6. `gpiod_request_config_new`
7. `gpiod_request_config_set_consumer`
8. `gpiod_chip_request_lines`
9. `gpiod_line_request_set_value` or `gpiod_line_request_set_values`

This is the right shape for Zig `@cImport` as well as plain C.

## C pattern for one DC motor

Assume:

- `ENA` on offset `18`
- `IN1` on offset `23`
- `IN2` on offset `24`
- all three lines are on `/dev/gpiochip0`

Adjust offsets to the actual target after running `gpioinfo`.

```c
#include <gpiod.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

enum { ENA = 18, IN1 = 23, IN2 = 24 };

static void fail(const char *msg)
{
    perror(msg);
    exit(1);
}

int main(void)
{
    struct gpiod_chip *chip = gpiod_chip_open("/dev/gpiochip0");
    if (!chip) fail("gpiod_chip_open");

    struct gpiod_line_settings *settings = gpiod_line_settings_new();
    if (!settings) fail("gpiod_line_settings_new");

    if (gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_OUTPUT))
        fail("gpiod_line_settings_set_direction");

    struct gpiod_line_config *line_cfg = gpiod_line_config_new();
    if (!line_cfg) fail("gpiod_line_config_new");

    unsigned int offsets[] = { ENA, IN1, IN2 };
    if (gpiod_line_config_add_line_settings(line_cfg, offsets, 3, settings))
        fail("gpiod_line_config_add_line_settings");

    enum gpiod_line_value initial[] = {
        GPIOD_LINE_VALUE_INACTIVE,
        GPIOD_LINE_VALUE_INACTIVE,
        GPIOD_LINE_VALUE_INACTIVE,
    };
    if (gpiod_line_config_set_output_values(line_cfg, initial, 3))
        fail("gpiod_line_config_set_output_values");

    struct gpiod_request_config *req_cfg = gpiod_request_config_new();
    if (!req_cfg) fail("gpiod_request_config_new");
    gpiod_request_config_set_consumer(req_cfg, "l298n-demo");

    struct gpiod_line_request *req =
        gpiod_chip_request_lines(chip, req_cfg, line_cfg);
    if (!req) fail("gpiod_chip_request_lines");

    enum gpiod_line_value forward[] = {
        GPIOD_LINE_VALUE_ACTIVE,
        GPIOD_LINE_VALUE_ACTIVE,
        GPIOD_LINE_VALUE_INACTIVE,
    };
    if (gpiod_line_request_set_values(req, forward))
        fail("gpiod_line_request_set_values(forward)");
    usleep(500000);

    enum gpiod_line_value reverse[] = {
        GPIOD_LINE_VALUE_ACTIVE,
        GPIOD_LINE_VALUE_INACTIVE,
        GPIOD_LINE_VALUE_ACTIVE,
    };
    if (gpiod_line_request_set_values(req, reverse))
        fail("gpiod_line_request_set_values(reverse)");
    usleep(500000);

    enum gpiod_line_value coast[] = {
        GPIOD_LINE_VALUE_INACTIVE,
        GPIOD_LINE_VALUE_INACTIVE,
        GPIOD_LINE_VALUE_INACTIVE,
    };
    if (gpiod_line_request_set_values(req, coast))
        fail("gpiod_line_request_set_values(coast)");

    gpiod_line_request_release(req);
    gpiod_request_config_free(req_cfg);
    gpiod_line_config_free(line_cfg);
    gpiod_line_settings_free(settings);
    gpiod_chip_close(chip);
    return 0;
}
```

Interpret the value order as:

- `ENA`: active means bridge enabled
- `IN1=1, IN2=0`: forward
- `IN1=0, IN2=1`: reverse
- `IN1=0, IN2=0` with `ENA=0`: coast
- `IN1=1, IN2=1` with `ENA=1`: brake

## Zig pattern via `@cImport`

Prefer importing the C API directly instead of creating a separate wrapper layer
unless the project needs one.

```zig
const std = @import("std");
const c = @cImport({
    @cInclude("gpiod.h");
});

const ENA: c_uint = 18;
const IN1: c_uint = 23;
const IN2: c_uint = 24;

fn check(ok: bool, what: []const u8) !void {
    if (!ok) {
        std.log.err("{s}", .{what});
        return error.GpioFailure;
    }
}

pub fn main() !void {
    const chip = c.gpiod_chip_open("/dev/gpiochip0");
    try check(chip != null, "gpiod_chip_open failed");
    defer c.gpiod_chip_close(chip);

    const settings = c.gpiod_line_settings_new();
    try check(settings != null, "gpiod_line_settings_new failed");
    defer c.gpiod_line_settings_free(settings);

    try check(
        c.gpiod_line_settings_set_direction(
            settings,
            c.GPIOD_LINE_DIRECTION_OUTPUT,
        ) == 0,
        "set_direction failed",
    );

    const line_cfg = c.gpiod_line_config_new();
    try check(line_cfg != null, "gpiod_line_config_new failed");
    defer c.gpiod_line_config_free(line_cfg);

    var offsets = [_]c_uint{ ENA, IN1, IN2 };
    try check(
        c.gpiod_line_config_add_line_settings(line_cfg, &offsets, offsets.len, settings) == 0,
        "add_line_settings failed",
    );

    var initial = [_]c.enum_gpiod_line_value{
        c.GPIOD_LINE_VALUE_INACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
    };
    try check(
        c.gpiod_line_config_set_output_values(line_cfg, &initial, initial.len) == 0,
        "set_output_values failed",
    );

    const req_cfg = c.gpiod_request_config_new();
    try check(req_cfg != null, "gpiod_request_config_new failed");
    defer c.gpiod_request_config_free(req_cfg);
    c.gpiod_request_config_set_consumer(req_cfg, "zig-l298n");

    const req = c.gpiod_chip_request_lines(chip, req_cfg, line_cfg);
    try check(req != null, "gpiod_chip_request_lines failed");
    defer c.gpiod_line_request_release(req);

    var forward = [_]c.enum_gpiod_line_value{
        c.GPIOD_LINE_VALUE_ACTIVE,
        c.GPIOD_LINE_VALUE_ACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
    };
    try check(c.gpiod_line_request_set_values(req, &forward) == 0, "forward failed");

    std.time.sleep(500 * std.time.ns_per_ms);

    var coast = [_]c.enum_gpiod_line_value{
        c.GPIOD_LINE_VALUE_INACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
    };
    try check(c.gpiod_line_request_set_values(req, &coast) == 0, "coast failed");
}
```

## PWM guidance

Treat `libgpiod` as a GPIO control API, not a dedicated PWM subsystem.

For L298N speed control:

- `ENA` and `ENB` can be toggled in software for coarse experiments
- user-space bit-banged PWM will have jitter and CPU overhead
- for stable speed control, prefer a hardware PWM-capable path exposed by Linux
  if the target image and pin assignment support it

If the user wants proper PWM, separate that question from the basic
`forward/backward/brake/coast` line-control logic.

## Two-motor pattern

For two motors, request:

- bridge A: `ENA`, `IN1`, `IN2`
- bridge B: `ENB`, `IN3`, `IN4`

Keep the values in a fixed array order and centralize the mapping. The most
common mistake is setting values against a different offset order than the one
used when making the request.

## Stepper pattern

For a bipolar stepper, request `IN1` through `IN4` and step through a coil
sequence by writing four output values at a time. Make the example slow, keep
the sequence explicit, and remind the user that the L298N is not a current-
regulated stepper driver.

## CLI tools for debugging

Use `gpiodetect`, `gpioinfo`, `gpioset`, and `gpioget` for bench debugging, but
do not build the motor runtime around shelling out to those tools from Zig.

## Sources

- Raspberry Pi GPIO best practices:
  https://pip-assets.raspberrypi.com/categories/685-whitepapers-app-notes/documents/RP-006553-WP/A-history-of-GPIO-usage-on-Raspberry-Pi-devices-and-current-best-practices
- Raspberry Pi GPIO docs:
  https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#gpio
- libgpiod chip API:
  https://libgpiod.readthedocs.io/en/latest/core_chips.html
- libgpiod line settings API:
  https://libgpiod.readthedocs.io/en/latest/core_line_settings.html
- libgpiod line config API:
  https://libgpiod.readthedocs.io/en/latest/core_line_config.html
- libgpiod request config API:
  https://libgpiod.readthedocs.io/en/latest/core_request_config.html
- libgpiod line request API:
  https://libgpiod.readthedocs.io/en/latest/core_line_request.html
