const std = @import("std");
const Allocator = std.mem.Allocator;

const main_compute = @import("main_compute");
const Streamer = @import("Streamer.zig");
const protocol = @import("protocol.zig");
const Mpsc = @import("channel.zig").Mpsc(protocol.Command);
const Tx = Mpsc.Tx;
const Rx = Mpsc.Rx;
const logging = @import("logging.zig");
const Gpio = @import("Gpio.zig");
const openzv = @import("openzv");

const SOCKET_PATH: []const u8 = "/tmp/main_compute.sock";

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logging.logFn,
};

// TODO: enrich this with other fields that are needed for our usecase
pub const PipelineCtx = struct {
    pub const Dir = enum {
        Left,
        Right,
        Center,
    };
    offset_dir: Dir,
};

fn preStart(allocator: Allocator) !Streamer {
    if (std.fs.accessAbsolute(SOCKET_PATH, .{})) |_| {
        try std.fs.deleteFileAbsolute(SOCKET_PATH);
    } else |_| {}

    return try Streamer.init(allocator, SOCKET_PATH);
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
        pub fn onMessage(alloc: Allocator, ctx: ?*anyopaque, msg: []const u8) anyerror!void {
            const tx_ptr: *const Tx = @ptrCast(@alignCast(ctx.?));
            const command = try protocol.Command.fromBytes(alloc, msg);
            try tx_ptr.send(command);
        }
    }.onMessage;

    var tx_ctx = tx;
    try streamer.serve(&tx_ctx, onMessage);
}

fn mainLoop(rx: Rx) !void {
    const log = std.log.scoped(.main_loop);

    const Chip = Gpio.Chip;
    const Bridge = Gpio.Bridge;
    const BridgePins = Gpio.BridgePins;

    // we are going to be using the following gpio pins:
    // Motor A (gpiochip0):
    // - 18 (ENA)
    // - 23 (IN1)
    // - 24 (IN2)
    //
    // Motor B (gpiochip0)
    // - 13 (ENB)
    // - 27 (IN3)
    // - 22 (IN4)
    const motor_a_bridge_pins: BridgePins = .{
        .enable = 18,
        .in1 = 23,
        .in2 = 24,
    };
    const motor_b_bridge_pins: BridgePins = .{
        .enable = 13,
        .in1 = 27,
        .in2 = 22,
    };

    // both sets are in the same /dev we only need one path
    const gpio_path = "/dev/gpiochip0";

    const chip = try Chip.open(gpio_path);
    defer chip.close();

    var bridge_a = try Bridge.init(chip, motor_a_bridge_pins, "Motor A");
    var bridge_b = try Bridge.init(chip, motor_b_bridge_pins, "Motor B");
    defer bridge_a.deinit();
    defer bridge_b.deinit();

    while (true) {
        const received = rx.recv() catch unreachable;
        log.info("received through spsc: {any}\n", .{received});

        switch (received) {
            // For now we'll mimic direction
            // left: a forward, b backward
            // right: b backward, b forward
            .direction => |dir| {
                switch (dir) {
                    .left => {
                        try bridge_a.drive(Gpio.Direction.forward, 50);
                        try bridge_b.drive(Gpio.Direction.backward, 50);
                    },
                    .right => {
                        try bridge_a.drive(Gpio.Direction.backward, 50);
                        try bridge_b.drive(Gpio.Direction.forward, 50);
                    },
                    .stop => {
                        try bridge_a.set(Gpio.Direction.brake);
                        try bridge_b.set(Gpio.Direction.brake);
                    },
                }
            },
        }
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
    // TODO: learn about different allocator types and choose a better (if
    // there is) to use
    const allocator = std.heap.page_allocator;

    var streamer = try preStart(allocator);
    defer streamer.deinit();

    try logging.init();
    defer logging.deinit();

    // This is just here to ensure we can deploy for now
    // TODO: remove this
    const version = openzv.opencvVersionMajor();
    const log = std.log.scoped(.main_entry);
    log.info("Running OpenCV version: {d}\n", .{version});

    const server_thread = try std.Thread.spawn(.{}, spawnServer, .{ allocator, SOCKET_PATH });
    defer server_thread.join();

    var spsc = try Mpsc.init(allocator, 10);
    const channel = spsc.split();
    const tx = channel.tx;
    const rx = channel.rx;

    const dispatch_thread = try std.Thread.spawn(.{}, spawnDispatcher, .{ tx, streamer });
    defer dispatch_thread.join();

    try mainLoop(rx);
}

test {
    _ = @import("channel.zig");
    _ = @import("protocol.zig");
    _ = @import("Gpio.zig");
    _ = @import("processors/Bottlecap.zig");
    const version = openzv.opencvVersionMajor();
    std.debug.print("version: {d}\n", .{version});
}
