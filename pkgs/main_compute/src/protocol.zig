const std = @import("std");

pub const Command = union(enum) {
    direction: Direction,

    pub fn stringify(self: Command, writer: *std.Io.Writer) !void {
        try std.json.Stringify.value(self, .{}, writer);
    }

    pub fn toOwnedBytes(self: Command, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();

        try self.stringify(&out.writer);
        return out.toOwnedSlice();
    }

    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Command {
        const parsed = try std.json.parseFromSlice(Command, allocator, bytes, .{});
        defer parsed.deinit();
        return parsed.value;
    }
};

pub const Direction = union(enum) {
    left: Payload,
    right: Payload,
    stop,

    pub const Payload = struct {
        speed: u8,
    };

    pub fn leftWithSpeed(speed: u8) Direction {
        return .{ .left = .{ .speed = speed } };
    }

    pub fn rightWithSpeed(speed: u8) Direction {
        return .{ .right = .{ .speed = speed } };
    }

    pub fn stringify(self: Direction, writer: *std.Io.Writer) !void {
        try std.json.Stringify.value(self, .{}, writer);
    }

    pub fn toOwnedBytes(self: Direction, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();

        try self.stringify(&out.writer);
        return out.toOwnedSlice();
    }

    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Direction {
        const parsed = try std.json.parseFromSlice(Direction, allocator, bytes, .{});
        defer parsed.deinit();
        return parsed.value;
    }
};

test "envelope to json bytes" {
    const allocator = std.testing.allocator;

    const direction = Direction.leftWithSpeed(42);
    const command = Command{ .direction = direction };
    const bytes = try command.toOwnedBytes(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqualStrings("{\"direction\":{\"left\":{\"speed\":42}}}", bytes);
}

test "envelope deserializes from json bytes" {
    const allocator = std.testing.allocator;

    const command = try Command.fromBytes(allocator, "{\"direction\":{\"left\":{\"speed\":42}}}");

    switch (command) {
        .direction => |dir| {
            switch (dir) {
                .left => |payload| try std.testing.expectEqual(42, payload.speed),
                else => return error.UnexpectedDirection,
            }
        },
    }
}

test "direction serializes to json bytes" {
    const allocator = std.testing.allocator;

    const direction = Direction.leftWithSpeed(42);
    const bytes = try direction.toOwnedBytes(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqualStrings("{\"left\":{\"speed\":42}}", bytes);
}

test "direction deserializes from json bytes" {
    const allocator = std.testing.allocator;

    const direction = try Direction.fromBytes(allocator, "{\"right\":{\"speed\":7}}");

    switch (direction) {
        .right => |payload| try std.testing.expectEqual(7, payload.speed),
        else => return error.UnexpectedDirection,
    }
}

test "stop command serializes to json bytes" {
    const allocator = std.testing.allocator;

    const command = Command{ .direction = .stop };
    const bytes = try command.toOwnedBytes(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqualStrings("{\"direction\":{\"stop\":{}}}", bytes);
}

test "stop direction deserializes from json bytes" {
    const allocator = std.testing.allocator;

    const direction = try Direction.fromBytes(allocator, "{\"stop\":{}}");

    switch (direction) {
        .stop => {},
        else => return error.UnexpectedDirection,
    }
}
