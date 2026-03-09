const std = @import("std");
const main_compute = @import("main_compute");
const Streamer = @import("Streamer.zig");

const SOCKET_PATH: []const u8 = "/tmp/main_compute.sock";

pub fn preStart() !Streamer {
    if (std.fs.accessAbsolute(SOCKET_PATH, .{})) |_| {
        try std.fs.deleteFileAbsolute(SOCKET_PATH);
    } else |_| {}

    return try Streamer.init(SOCKET_PATH);
}

pub fn main() !void {
    var streamer = try preStart();
    defer streamer.deinit();

    var buf: [4096]u8 = undefined;
    try streamer.listenAndExecute(&buf, null, onMessage);
}

fn onMessage(_: ?*anyopaque, msg: []const u8) !void {
    std.debug.print("recv: {s}\n", .{msg});
}
