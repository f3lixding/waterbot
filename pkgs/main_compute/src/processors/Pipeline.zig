const std = @import("std");
const Allocator = std.mem.Allocator;
const logging = std.log.scoped(.main_pipeline);

const Self = @This();
const EgressTx = @import("../main.zig").Tx;
const Mpsc = @import("../channel.zig").Mpsc(OrderDetail);
const OrderRx = Mpsc.Rx;
const OrderTx = Mpsc.Tx;
const Pipeline = @import("pp").Pipeline;
const PipelineCtx = @import("../main.zig").PipelineCtx;
const PipelineConfig = @import("pp").Pipeline.PipelineConfig;
const Command = @import("../protocol.zig").Command;

pub const OrderDetail = enum {
    UntilCompliant,
};

order_tx: OrderTx,
order_rx: OrderRx,
egress_tx: *EgressTx,
pipeline: Pipeline,
allocator: Allocator,
channel: Mpsc,

pub fn init(allocator: Allocator, pc: PipelineConfig, egress_tx: *EgressTx) !Self {
    const pipeline = try Pipeline.init(allocator, pc);
    var channel = try Mpsc.init(allocator, 50);
    const split = channel.split();
    const order_tx = split.tx;
    const order_rx = split.rx;

    return .{
        .order_tx = order_tx,
        .order_rx = order_rx,
        .egress_tx = egress_tx,
        .pipeline = pipeline,
        .allocator = allocator,
        .channel = channel,
    };
}

pub fn deinit(self: *Self) void {
    const egress_tx = self.egress_tx;
    const pipeline = &self.pipeline;
    const channel = &self.channel;

    egress_tx.close();
    pipeline.deinit();
    channel.deinit();
}

/// This runs the pipeline in a loop
/// Currently there is no way to interrupt a loop that is in progress
pub fn run(self: *Self) !void {
    var should_run: bool = false;
    while (true) {
        const pipeline = &self.pipeline;
        if (!should_run) {
            const order_detail = self.order_rx.recv() catch |e| {
                logging.err("Ingress Rx failing to receive: {any}", .{e});
                return;
            };
            if (order_detail == .UntilCompliant) {
                should_run = true;
            }
        }

        var ctx: PipelineCtx = undefined;
        pipeline.tick(@ptrCast(&ctx)) catch |e| {
            logging.err("Pipeline has failed to tick: {any}", .{e});
            ctx.offset_dir = .Center;
        };

        const command = commandForOffset(ctx.offset_dir);
        self.egress_tx.send(command) catch |e| {
            logging.err("Pipeline has failed to send result: {any}", .{e});
        };
        if (ctx.offset_dir == .Center) {
            should_run = false;
        }
    }
}

pub fn orderUp(self: *Self, order_detail: OrderDetail) !void {
    try self.order_tx.send(order_detail);
}

fn commandForOffset(dir: PipelineCtx.Dir) Command {
    return switch (dir) {
        .Center => .compliant,
        .Left => .{ .direction = .{ .left = .{ .speed = 20 } } },
        .Right => .{ .direction = .{ .right = .{ .speed = 20 } } },
    };
}

test "orderUp enqueues order detail" {
    const allocator = std.testing.allocator;
    var egress_channel = try @import("../channel.zig").Mpsc(Command).init(allocator, 1);
    defer egress_channel.deinit();

    var egress_split = egress_channel.split();
    var pipeline = try Self.init(allocator, .{ .stages = &.{} }, &egress_split.tx);
    defer pipeline.deinit();

    try pipeline.orderUp(.UntilCompliant);
    try std.testing.expectEqual(.UntilCompliant, try pipeline.order_rx.recv());
}

test "commandForOffset maps center to compliant" {
    const command = commandForOffset(.Center);

    switch (command) {
        .compliant => {},
        else => return error.UnexpectedCommand,
    }
}

test "commandForOffset maps left to left direction" {
    const command = commandForOffset(.Left);

    switch (command) {
        .direction => |dir| switch (dir) {
            .left => |payload| try std.testing.expectEqual(@as(u8, 20), payload.speed),
            else => return error.UnexpectedDirection,
        },
        else => return error.UnexpectedCommand,
    }
}

test "commandForOffset maps right to right direction" {
    const command = commandForOffset(.Right);

    switch (command) {
        .direction => |dir| switch (dir) {
            .right => |payload| try std.testing.expectEqual(@as(u8, 20), payload.speed),
            else => return error.UnexpectedDirection,
        },
        else => return error.UnexpectedCommand,
    }
}
