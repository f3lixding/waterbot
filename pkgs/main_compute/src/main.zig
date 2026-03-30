const std = @import("std");
const Allocator = std.mem.Allocator;

const main_compute = @import("main_compute");
const Streamer = @import("Streamer.zig");
const protocol = @import("protocol.zig");
const Mpsc = @import("channel.zig").Mpsc(protocol.Command);
pub const Tx = Mpsc.Tx;
const Rx = Mpsc.Rx;
const logging = @import("logging.zig");
const Gpio = @import("Gpio.zig");
const openzv = @import("openzv");
const Pipeline = @import("processors/Pipeline.zig");
const PerceptionSpec = @import("pp").PerceptionSpec;
const PipelineStage = @import("pp").Pipeline.Stage;
const BottleCapProcessor = @import("processors/Bottlecap.zig");
const Processor = @import("pp").Processor;
pub const CvOrderTx = Pipeline.OrderTx;

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
        NotFound,
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
    cv_order_tx: *CvOrderTx, // This is for testing only. It dispatches order to the cv pipeline via the UI
) !void {
    const Server = @import("Server.zig");
    try Server.run(allocator, socket_path, cv_order_tx);
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

// TODO: rewrite this loop with the following structure:
//   while (true) {
//       while (rx.tryRecv()) |cmd| {
//           updateDesiredState(cmd);
//       } else |err| switch (err) {
//           error.WouldBlock => {},
//           else => return err,
//       }
//
//       readLatestSensors();
//       updateEstimator();
//       runController();
//       applyMotorOutputs();
//       enforceSafetyTimeouts();
//       sleepUntilNextTick();
//   }
//   This would effectively turn this into a
//   [super loop](https://stackoverflow.com/questions/44429456/what-is-super-loop-in-embedded-c-programming-language)
fn commandActuatorSuperLoop(rx: Rx) !void {
    const log = std.log.scoped(.main_loop);
    log.info("command actuator loop initialized", .{});

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

    log.info("opening gpio chip: {s}", .{gpio_path});
    const chip = try Chip.open(gpio_path);
    defer chip.close();
    log.info("opened gpio chip", .{});

    log.info("initializing motor A bridge", .{});
    var bridge_a = try Bridge.init(chip, motor_a_bridge_pins, "Motor A");
    log.info("motor A bridge ready", .{});
    log.info("initializing motor B bridge", .{});
    var bridge_b = try Bridge.init(chip, motor_b_bridge_pins, "Motor B");
    log.info("motor B bridge ready", .{});
    defer bridge_a.deinit();
    defer bridge_b.deinit();

    while (true) {
        log.info("waiting for command", .{});
        const received = rx.recv() catch unreachable;
        log.info("received through spsc: {any}", .{received});

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
            .compliant => {
                // noop,
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
/// - Initiate the command actuator loop routine (this is the brain that
/// actually affects the GPIOs)
pub fn main() !void {
    // TODO: learn about different allocator types and choose a better (if
    // there is) to use
    const allocator = std.heap.page_allocator;

    const cap_level: std.log.Level = blk: {
        const cap_level_str = std.process.getEnvVarOwned(allocator, "LOG_LEVEL") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk .info,
            else => return err,
        };
        defer allocator.free(cap_level_str);

        if (std.mem.eql(u8, cap_level_str, "debug")) break :blk .debug;
        if (std.mem.eql(u8, cap_level_str, "info")) break :blk .info;
        if (std.mem.eql(u8, cap_level_str, "warn")) break :blk .warn;
        if (std.mem.eql(u8, cap_level_str, "err")) break :blk .err;
        if (std.mem.eql(u8, cap_level_str, "error")) break :blk .err;

        break :blk .info;
    };

    var streamer = try preStart(allocator);
    defer streamer.deinit();

    try logging.init(cap_level);
    defer logging.deinit();

    // This is just here to ensure we can deploy for now
    // TODO: remove this
    const version = openzv.opencvVersionMajor();
    const log = std.log.scoped(.main_entry);
    log.info("Running OpenCV version: {d}", .{version});

    var mpsc = try Mpsc.init(allocator, 10);
    const channel = mpsc.split();
    var tx = channel.tx;
    const rx = channel.rx;

    const dispatch_thread = std.Thread.spawn(.{}, spawnDispatcher, .{ tx, streamer }) catch |e| {
        log.err("Dispatch thread failed to spawn: {any}", .{e});
        return e;
    };

    // TODO: move this to a more purposeful place
    var bc = BottleCapProcessor.init(allocator);
    defer bc.deinit();
    const bcp = Processor.initAsProcessor(PipelineCtx, BottleCapProcessor, &bc);
    const stages = [_]PipelineStage{
        .{
            .perception = PerceptionSpec{ .Vision = .{} },
            .processor = bcp,
        },
    };
    var pipeline = Pipeline.init(allocator, .{
        .stages = stages[0..],
    }, &tx) catch |e| {
        log.err("Error initializing pipeline: {any}", .{e});
        return e;
    };
    const order_tx = &pipeline.order_tx;
    defer pipeline.deinit();

    const server_thread = std.Thread.spawn(.{}, spawnServer, .{ allocator, SOCKET_PATH, order_tx }) catch |e| {
        log.err("Server thread failed to spawn: {any}", .{e});
        return e;
    };

    const cv_pipeline = std.Thread.spawn(.{}, Pipeline.run, .{&pipeline}) catch |e| {
        log.err("CV pipeline thread failed to spawn: {any}", .{e});
        return e;
    };

    defer cv_pipeline.join();
    defer server_thread.join();
    defer dispatch_thread.join();

    log.info("entering command actuator loop", .{});
    try commandActuatorSuperLoop(rx);
}

test {
    _ = @import("channel.zig");
    _ = @import("protocol.zig");
    _ = @import("Gpio.zig");
    _ = @import("processors/Bottlecap.zig");
    _ = @import("processors/Pipeline.zig");
}
