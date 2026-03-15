const std = @import("std");
const Allocator = std.mem.Allocator;

const main_compute = @import("main_compute");
const Streamer = @import("Streamer.zig");
const Spsc = @import("channel.zig").Spsc(usize);
const Tx = Spsc.Tx;
const Rx = Spsc.Rx;
const logging = @import("logging.zig");

const SOCKET_PATH: []const u8 = "/tmp/main_compute.sock";

const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
};

fn preStart() !Streamer {
    if (std.fs.accessAbsolute(SOCKET_PATH, .{})) |_| {
        try std.fs.deleteFileAbsolute(SOCKET_PATH);
    } else |_| {}

    return try Streamer.init(SOCKET_PATH);
}

fn spawnServer(
    allocator: Allocator,
    socket_path: []const u8,
) !void {
    const Server = @import("Server.zig");
    try Server.run(allocator, socket_path);
}

fn spawnDispatcher(tx: Tx, streamer: Streamer) !void {
    const onMessage = struct {
        pub fn onMessage(ctx: ?*anyopaque, msg: []const u8) anyerror!void {
            const tx_ptr: *const Tx = @ptrCast(@alignCast(ctx.?));
            std.debug.print("recv: {s}\n", .{msg});
            try tx_ptr.send(10);
        }
    }.onMessage;

    var buf: [4096]u8 = undefined;
    var tx_ctx = tx;
    try streamer.listenAndExecute(&buf, &tx_ctx, onMessage);
}

fn mainLoop(rx: Rx) !void {
    while (true) {
        const received = rx.recv() catch unreachable;
        std.debug.print("recevied through spsc: {d}\n", .{received});
    }
}

/// The entry point to main compute, which has the following responsibilities:
///
/// - Prime and prep the UDS socket - Spawn the http server in a thread (or a
/// process, pending future developement)
///
/// - Spawn the dispatch thread
///
/// - Initiate the main loop routine (this is the brain that actually affects the
/// GPIOs)
pub fn main() !void {
    var streamer = try preStart();
    defer streamer.deinit();

    // TODO: learn about different allocator types and choose a better (if
    // there is) to use
    const allocator = std.heap.page_allocator;

    try logging.init();
    defer logging.deinit();

    const server_thread = try std.Thread.spawn(.{}, spawnServer, .{ allocator, SOCKET_PATH });
    defer server_thread.join();

    var spsc = try Spsc.init(allocator, 10);
    const channel = spsc.split();
    const tx = channel.tx;
    const rx = channel.rx;

    const dispatch_thread = try std.Thread.spawn(.{}, spawnDispatcher, .{ tx, streamer });
    defer dispatch_thread.join();

    try mainLoop(rx);
}

test {
    _ = @import("channel.zig");
}
