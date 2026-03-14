const std = @import("std");

pub const c = @cImport({
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
    handle: *c.gpiod_chip,

    pub fn open(path: [:0]const u8) !Chip {
        const handle = c.gpiod_chip_open(path.ptr) orelse return error.OpenChipFailed;
        return .{ .handle = handle };
    }

    pub fn close(self: Chip) void {
        c.gpiod_chip_close(self.handle);
    }
};

pub const Bridge = struct {
    request: *c.gpiod_line_request,

    pub fn init(chip: Chip, pins: BridgePins, consumer: [:0]const u8) !Bridge {
        const settings = c.gpiod_line_settings_new() orelse return error.OutOfMemory;
        defer c.gpiod_line_settings_free(settings);

        if (c.gpiod_line_settings_set_direction(settings, c.GPIOD_LINE_DIRECTION_OUTPUT) != 0) {
            return error.SetDirectionFailed;
        }

        const line_config = c.gpiod_line_config_new() orelse return error.OutOfMemory;
        defer c.gpiod_line_config_free(line_config);

        var offsets = [_]c_uint{ pins.enable, pins.in1, pins.in2 };
        if (c.gpiod_line_config_add_line_settings(
            line_config,
            &offsets,
            offsets.len,
            settings,
        ) != 0) {
            return error.ConfigureLinesFailed;
        }

        var initial = inactiveTriplet();
        if (c.gpiod_line_config_set_output_values(line_config, &initial, initial.len) != 0) {
            return error.ConfigureLinesFailed;
        }

        const request_config = c.gpiod_request_config_new() orelse return error.OutOfMemory;
        defer c.gpiod_request_config_free(request_config);

        c.gpiod_request_config_set_consumer(request_config, consumer.ptr);

        const request = c.gpiod_chip_request_lines(
            chip.handle,
            request_config,
            line_config,
        ) orelse return error.RequestLinesFailed;

        return .{ .request = request };
    }

    pub fn deinit(self: Bridge) void {
        c.gpiod_line_request_release(self.request);
    }

    pub fn set(self: Bridge, direction: Direction) !void {
        var values = switch (direction) {
            .forward => activeTriplet(c.GPIOD_LINE_VALUE_ACTIVE, c.GPIOD_LINE_VALUE_INACTIVE),
            .backward => activeTriplet(c.GPIOD_LINE_VALUE_INACTIVE, c.GPIOD_LINE_VALUE_ACTIVE),
            .coast => inactiveTriplet(),
            .brake => activeTriplet(c.GPIOD_LINE_VALUE_ACTIVE, c.GPIOD_LINE_VALUE_ACTIVE),
        };

        if (c.gpiod_line_request_set_values(self.request, &values) != 0) {
            return error.SetValuesFailed;
        }
    }
};

fn activeTriplet(in1: c.enum_gpiod_line_value, in2: c.enum_gpiod_line_value) [3]c.enum_gpiod_line_value {
    return .{
        c.GPIOD_LINE_VALUE_ACTIVE,
        in1,
        in2,
    };
}

fn inactiveTriplet() [3]c.enum_gpiod_line_value {
    return .{
        c.GPIOD_LINE_VALUE_INACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
        c.GPIOD_LINE_VALUE_INACTIVE,
    };
}

test "triplet helpers map expected states" {
    const forward = activeTriplet(c.GPIOD_LINE_VALUE_ACTIVE, c.GPIOD_LINE_VALUE_INACTIVE);
    try std.testing.expectEqual(c.GPIOD_LINE_VALUE_ACTIVE, forward[0]);
    try std.testing.expectEqual(c.GPIOD_LINE_VALUE_ACTIVE, forward[1]);
    try std.testing.expectEqual(c.GPIOD_LINE_VALUE_INACTIVE, forward[2]);

    const coast = inactiveTriplet();
    try std.testing.expectEqual(c.GPIOD_LINE_VALUE_INACTIVE, coast[0]);
    try std.testing.expectEqual(c.GPIOD_LINE_VALUE_INACTIVE, coast[1]);
    try std.testing.expectEqual(c.GPIOD_LINE_VALUE_INACTIVE, coast[2]);
}
