//! This is modeled after H bridge hardware abstraction level
//! We do this because of the following reasons:
//! - we get to work with motor semantics (e.g. forward and backwards) instead
//!   of raw GPIO bit patterns.
//! - the GPIO-to-driver mapping is centralized in one place
//! - invalid or inconsistent pin combination are less likely to leak into the
//!   rest of the code

const std = @import("std");

pub const Gpio = @cImport({
    @cInclude("gpiod.h");
});

pub const Direction = enum {
    forward,
    backward,
    coast,
    brake,
};

pub const BridgePins = struct {
    enable: c_uint,
    in1: c_uint,
    in2: c_uint,
};

pub const Chip = struct {
    handle: *Gpio.gpiod_chip,

    pub fn open(path: [:0]const u8) !Chip {
        const handle = Gpio.gpiod_chip_open(path.ptr) orelse return error.OpenChipFailed;
        return .{ .handle = handle };
    }

    pub fn close(self: Chip) void {
        Gpio.gpiod_chip_close(self.handle);
    }
};

pub const Bridge = struct {
    request: *Gpio.gpiod_line_request,

    /// Initializes control of one H-bridge channel through three GPIO pins:
    /// `enable`, `in1`, and `in2`.
    ///
    /// In libgpiod terminology, a "line" is one GPIO pin. This function uses
    /// three lines because the motor driver is controlled by three separate
    /// pins.
    ///
    /// A "line settings" object describes how a line should behave. Here, the
    /// settings say that the lines are outputs, meaning this program will drive
    /// the pins high or low rather than read them as inputs.
    ///
    /// A "line config" object maps one settings object onto one or more lines.
    /// In this case, the same output settings are applied to the three GPIO
    /// lines identified by `pins.enable`, `pins.in1`, and `pins.in2`.
    ///
    /// The initial values are set to inactive before the request is made so the
    /// bridge starts in a neutral state instead of briefly driving the motor.
    ///
    /// The consumer label is a human-readable name recorded by the kernel for
    /// debugging and inspection tools.
    ///
    /// Requesting the lines gives this process exclusive use of those GPIOs so
    /// another process cannot also try to drive the same motor-control pins at
    /// the same time.
    pub fn init(chip: Chip, pins: BridgePins, consumer: [:0]const u8) !Bridge {
        const settings = Gpio.gpiod_line_settings_new() orelse return error.OutOfMemory;
        defer Gpio.gpiod_line_settings_free(settings);

        if (Gpio.gpiod_line_settings_set_direction(settings, Gpio.GPIOD_LINE_DIRECTION_OUTPUT) != 0) {
            return error.SetDirectionFailed;
        }

        const line_config = Gpio.gpiod_line_config_new() orelse return error.OutOfMemory;
        defer Gpio.gpiod_line_config_free(line_config);

        var offsets = [_]c_uint{ pins.enable, pins.in1, pins.in2 };
        if (Gpio.gpiod_line_config_add_line_settings(
            line_config,
            &offsets,
            offsets.len,
            settings,
        ) != 0) {
            return error.ConfigureLinesFailed;
        }

        var initial = inactiveTriplet();
        if (Gpio.gpiod_line_config_set_output_values(line_config, &initial, initial.len) != 0) {
            return error.ConfigureLinesFailed;
        }

        const request_config = Gpio.gpiod_request_config_new() orelse return error.OutOfMemory;
        defer Gpio.gpiod_request_config_free(request_config);

        Gpio.gpiod_request_config_set_consumer(request_config, consumer.ptr);

        const request = Gpio.gpiod_chip_request_lines(
            chip.handle,
            request_config,
            line_config,
        ) orelse return error.RequestLinesFailed;

        return .{ .request = request };
    }

    pub fn deinit(self: Bridge) void {
        Gpio.gpiod_line_request_release(self.request);
    }

    pub fn set(self: Bridge, direction: Direction) !void {
        var values = switch (direction) {
            .forward => activeTriplet(Gpio.GPIOD_LINE_VALUE_ACTIVE, Gpio.GPIOD_LINE_VALUE_INACTIVE),
            .backward => activeTriplet(Gpio.GPIOD_LINE_VALUE_INACTIVE, Gpio.GPIOD_LINE_VALUE_ACTIVE),
            .coast => inactiveTriplet(),
            .brake => activeTriplet(Gpio.GPIOD_LINE_VALUE_ACTIVE, Gpio.GPIOD_LINE_VALUE_ACTIVE),
        };

        if (Gpio.gpiod_line_request_set_values(self.request, &values) != 0) {
            return error.SetValuesFailed;
        }
    }
};

fn activeTriplet(in1: Gpio.enum_gpiod_line_value, in2: Gpio.enum_gpiod_line_value) [3]Gpio.enum_gpiod_line_value {
    return .{
        Gpio.GPIOD_LINE_VALUE_ACTIVE,
        in1,
        in2,
    };
}

fn inactiveTriplet() [3]Gpio.enum_gpiod_line_value {
    return .{
        Gpio.GPIOD_LINE_VALUE_INACTIVE,
        Gpio.GPIOD_LINE_VALUE_INACTIVE,
        Gpio.GPIOD_LINE_VALUE_INACTIVE,
    };
}

test "triplet helpers map expected states" {
    const forward = activeTriplet(Gpio.GPIOD_LINE_VALUE_ACTIVE, Gpio.GPIOD_LINE_VALUE_INACTIVE);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, forward[0]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, forward[1]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, forward[2]);

    const coast = inactiveTriplet();
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, coast[0]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, coast[1]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, coast[2]);
}
