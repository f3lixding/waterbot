//! This is modeled after H bridge hardware abstraction level
//! We do this because of the following reasons:
//! - we get to work with motor semantics (e.g. forward and backwards) instead
//!   of raw GPIO bit patterns.
//! - the GPIO-to-driver mapping is centralized in one place
//! - invalid or inconsistent pin combination are less likely to leak into the
//!   rest of the code

const std = @import("std");
const log = std.log.scoped(.gpio);

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
    const pwm_period_ns = 20 * std.time.ns_per_ms;
    const State = struct {
        io: std.Io,
        mutex: std.Io.Mutex = .init,
        direction: Direction = .coast,
        speed_percent: u8 = 0,
        running: bool = true,
    };

    request: *Gpio.gpiod_line_request,
    state: *State,
    worker: std.Thread,

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
    pub fn init(chip: Chip, pins: BridgePins, consumer: [:0]const u8, io: std.Io) !Bridge {
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

        const state = try std.heap.page_allocator.create(State);
        errdefer std.heap.page_allocator.destroy(state);
        state.* = .{ .io = io };

        const worker = try std.Thread.spawn(.{}, pwmWorker, .{ request, state });

        return .{
            .request = request,
            .state = state,
            .worker = worker,
        };
    }

    pub fn deinit(self: *Bridge) void {
        self.state.mutex.lockUncancelable(self.state.io);
        self.state.running = false;
        self.state.mutex.unlock(self.state.io);

        self.worker.join();
        _ = setValues(self.request, inactiveTriplet()) catch {};
        Gpio.gpiod_line_request_release(self.request);
        std.heap.page_allocator.destroy(self.state);
    }

    /// Sets the bridge state directly.
    ///
    /// `forward` and `backward` run at 100% duty cycle. Use `drive` or
    /// `setSpeed` for variable speed.
    pub fn set(self: *Bridge, direction: Direction) !void {
        const speed_percent: u8 = switch (direction) {
            .forward, .backward => 100,
            .coast, .brake => 0,
        };

        try self.updateState(direction, speed_percent);
    }

    /// Runs the bridge in `direction` using software PWM on the `enable` pin.
    ///
    /// `speed_percent` is a duty cycle from `0` to `100`.
    pub fn drive(self: *Bridge, direction: Direction, speed_percent: u8) !void {
        if (speed_percent > 100) return error.InvalidSpeed;
        try self.updateState(direction, speed_percent);
    }

    /// Updates speed while preserving the current direction.
    ///
    /// This is only meaningful when the current direction is `forward` or
    /// `backward`.
    pub fn setSpeed(self: *Bridge, speed_percent: u8) !void {
        if (speed_percent > 100) return error.InvalidSpeed;

        self.state.mutex.lockUncancelable(self.state.io);
        const direction = self.state.direction;
        self.state.mutex.unlock(self.state.io);

        switch (direction) {
            .forward, .backward => try self.updateState(direction, speed_percent),
            .coast, .brake => return error.SpeedRequiresDriveDirection,
        }
    }

    fn updateState(self: *Bridge, direction: Direction, speed_percent: u8) !void {
        self.state.mutex.lockUncancelable(self.state.io);
        defer self.state.mutex.unlock(self.state.io);

        self.state.direction = direction;
        self.state.speed_percent = speed_percent;
    }

    /// This is a software PWM. This is to be ran in the background in a hot loop.
    /// In the absence of a hardware PWM, this is typically how PWM is done:
    /// - read shared state
    /// - derive the phase, if we're in pwm phase, we need to set value of on
    ///   for a percentage of the duty cycle to achieve the desired speed
    ///
    /// There are some pins that are some PWM pins on the raspberry pi.
    /// If we do end up using those pins, this is probably not needed.
    /// TODO: conditionally exclude this thread when PWM pins are used.
    fn pwmWorker(request: *Gpio.gpiod_line_request, state: *State) void {
        var last_values = inactiveTriplet();

        while (true) {
            state.mutex.lockUncancelable(state.io);
            const running = state.running;
            const direction = state.direction;
            const speed_percent = state.speed_percent;
            state.mutex.unlock(state.io);

            if (!running) break;

            const phase = phaseFor(direction, speed_percent);
            switch (phase) {
                .steady => |values| {
                    if (!tripletsEqual(last_values, values)) {
                        setValues(request, values) catch {};
                        last_values = values;
                    }
                    state.io.sleep(.fromNanoseconds(pwm_period_ns), .awake) catch unreachable;
                },
                .pwm => |pwm| {
                    if (!tripletsEqual(last_values, pwm.active)) {
                        setValues(request, pwm.active) catch {};
                        last_values = pwm.active;
                    }
                    state.io.sleep(.fromNanoseconds(pwm.high_ns), .awake) catch unreachable;

                    state.mutex.lockUncancelable(state.io);
                    const still_running = state.running;
                    state.mutex.unlock(state.io);
                    if (!still_running) break;

                    if (!tripletsEqual(last_values, pwm.inactive)) {
                        setValues(request, pwm.inactive) catch {};
                        last_values = pwm.inactive;
                    }
                    state.io.sleep(.fromNanoseconds(pwm.low_ns), .awake) catch unreachable;
                },
            }
        }
    }
};

const Phase = union(enum) {
    steady: [3]Gpio.enum_gpiod_line_value,
    pwm: struct {
        active: [3]Gpio.enum_gpiod_line_value,
        inactive: [3]Gpio.enum_gpiod_line_value,
        high_ns: u64,
        low_ns: u64,
    },
};

fn activeTriplet(
    enable: Gpio.enum_gpiod_line_value,
    in1: Gpio.enum_gpiod_line_value,
    in2: Gpio.enum_gpiod_line_value,
) [3]Gpio.enum_gpiod_line_value {
    return .{
        enable,
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

fn forwardTriplet(enable: Gpio.enum_gpiod_line_value) [3]Gpio.enum_gpiod_line_value {
    return activeTriplet(enable, Gpio.GPIOD_LINE_VALUE_ACTIVE, Gpio.GPIOD_LINE_VALUE_INACTIVE);
}

fn backwardTriplet(enable: Gpio.enum_gpiod_line_value) [3]Gpio.enum_gpiod_line_value {
    return activeTriplet(enable, Gpio.GPIOD_LINE_VALUE_INACTIVE, Gpio.GPIOD_LINE_VALUE_ACTIVE);
}

fn brakeTriplet() [3]Gpio.enum_gpiod_line_value {
    return activeTriplet(
        Gpio.GPIOD_LINE_VALUE_ACTIVE,
        Gpio.GPIOD_LINE_VALUE_ACTIVE,
        Gpio.GPIOD_LINE_VALUE_ACTIVE,
    );
}

fn phaseFor(direction: Direction, speed_percent: u8) Phase {
    return switch (direction) {
        .coast => .{ .steady = inactiveTriplet() },
        .brake => .{ .steady = brakeTriplet() },
        .forward => directionalPhase(forwardTriplet, speed_percent),
        .backward => directionalPhase(backwardTriplet, speed_percent),
    };
}

fn directionalPhase(
    comptime tripletFn: fn (Gpio.enum_gpiod_line_value) [3]Gpio.enum_gpiod_line_value,
    speed_percent: u8,
) Phase {
    if (speed_percent == 0) return .{ .steady = inactiveTriplet() };
    if (speed_percent >= 100) return .{ .steady = tripletFn(Gpio.GPIOD_LINE_VALUE_ACTIVE) };

    const high_ns = (@as(u64, Bridge.pwm_period_ns) * speed_percent) / 100;
    const low_ns = @as(u64, Bridge.pwm_period_ns) - high_ns;

    return .{
        .pwm = .{
            .active = tripletFn(Gpio.GPIOD_LINE_VALUE_ACTIVE),
            .inactive = tripletFn(Gpio.GPIOD_LINE_VALUE_INACTIVE),
            .high_ns = high_ns,
            .low_ns = low_ns,
        },
    };
}

fn setValues(request: *Gpio.gpiod_line_request, values: [3]Gpio.enum_gpiod_line_value) !void {
    var mutable = values;
    if (Gpio.gpiod_line_request_set_values(request, &mutable) != 0) {
        return error.SetValuesFailed;
    }
}

fn tripletsEqual(
    a: [3]Gpio.enum_gpiod_line_value,
    b: [3]Gpio.enum_gpiod_line_value,
) bool {
    return a[0] == b[0] and a[1] == b[1] and a[2] == b[2];
}

test "triplet helpers map expected states" {
    const forward = forwardTriplet(Gpio.GPIOD_LINE_VALUE_ACTIVE);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, forward[0]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, forward[1]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, forward[2]);

    const coast = inactiveTriplet();
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, coast[0]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, coast[1]);
    try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, coast[2]);
}

test "phase uses pwm for partial forward speed" {
    const phase = phaseFor(.forward, 25);

    switch (phase) {
        .steady => return error.ExpectedPwmPhase,
        .pwm => |pwm| {
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, pwm.active[0]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, pwm.active[1]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, pwm.active[2]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, pwm.inactive[0]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, pwm.inactive[1]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_INACTIVE, pwm.inactive[2]);
            try std.testing.expectEqual(@as(u64, 5 * std.time.ns_per_ms), pwm.high_ns);
            try std.testing.expectEqual(@as(u64, 15 * std.time.ns_per_ms), pwm.low_ns);
        },
    }
}

test "phase keeps brake steady regardless of speed" {
    const phase = phaseFor(.brake, 10);

    switch (phase) {
        .steady => |values| {
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, values[0]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, values[1]);
            try std.testing.expectEqual(Gpio.GPIOD_LINE_VALUE_ACTIVE, values[2]);
        },
        .pwm => return error.ExpectedSteadyPhase,
    }
}
