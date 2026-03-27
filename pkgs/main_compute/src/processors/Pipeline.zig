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
    const channel = try Mpsc.init(allocator, 50);
    const split = channel.split();
    const order_rx = split.rx;

    return .{
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

        switch (ctx.offset_dir) {
            .Center => {
                self.egress_tx.send(.compliant) catch |e| {
                    logging.err("Pipeline has failed to send result: {any}", .{e});
                };
                should_run = false;
            },
            .Left => {
                self.egress_tx.send(
                    .{
                        .direction = .{ .left = .{ .speed = 20 } },
                    },
                ) catch |e| {
                    logging.err("Pipeline has failed to send result: {any}", .{e});
                };
            },
            .Right => {
                self.egress_tx.send(
                    .{
                        .direction = .{ .right = .{ .speed = 20 } },
                    },
                ) catch |e| {
                    logging.err("Pipeline has failed to send result: {any}", .{e});
                };
            },
        }
    }
}

pub fn orderUp(self: *Self, order_detail: OrderDetail) !void {
    try self.order_tx.send(order_detail);
}
