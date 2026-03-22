//! This is the top level abstraction most consumer should be using
//! The pipeline is composed of one or more Processors, which is just a
//! dependency graph with each node being their own Processor
//! Like all dependency graph, in theory they can be a DAG, but for now we will
//! stick with a line
const std = @import("std");
const Allocator = std.mem.Allocator;

const Processor = @import("Processor.zig");
const Frame = @import("root.zig").Frame;
const PerceptionSpec = @import("root.zig").PerceptionSpec;

pub const Stage = struct {
    perception: PerceptionSpec,
    processor: Processor,
    depends_on: []const usize = &.{},
};

const Self = @This();

pub const PipelineConfig = struct {
    stages: []const Stage,
};

allocator: Allocator,
stages: []Stage,

pub fn init(alloc: Allocator, config: PipelineConfig) !Self {
    var stages = try alloc.alloc(Stage, config.stages.len);
    errdefer alloc.free(stages);
    var owned_dep_count: usize = 0;
    errdefer {
        for (stages[0..owned_dep_count]) |stage| {
            alloc.free(stage.depends_on);
        }
    }

    for (config.stages, 0..) |stage, i| {
        stages[i] = stage;
        stages[i].depends_on = try alloc.dupe(usize, stage.depends_on);
        owned_dep_count = i + 1;
    }

    try validateStages(stages);

    return .{
        .allocator = alloc,
        .stages = stages,
    };
}

fn validateStages(stages: []const Stage) !void {
    for (stages, 0..) |stage, i| {
        switch (stage.perception) {
            .Vision => {},
            else => return error.UnsupportedPerceptionStage,
        }

        for (stage.depends_on) |depends_on| {
            if (depends_on >= stages.len) return error.InvalidStageDependency;
            if (depends_on >= i) return error.StageDependencyMustPrecedeConsumer;
        }
    }
}

pub fn deinit(self: *Self) void {
    for (self.stages) |stage| {
        self.allocator.free(stage.depends_on);
    }
    self.allocator.free(self.stages);
    self.* = undefined;
}

pub fn tick(self: Self, ctx: *anyopaque, frame: Frame) !void {
    for (self.stages) |stage| {
        try stage.processor.process(ctx, frame);
    }
}

test "pipeline ticks stages in order" {
    const Ctx = struct {
        calls: [2]u8 = .{ 0, 0 },
        next_idx: usize = 0,
    };

    const Recorder = struct {
        id: u8,

        pub fn process(self: *@This(), ctx: *Ctx, frame: Frame) !void {
            _ = frame;
            ctx.calls[ctx.next_idx] = self.id;
            ctx.next_idx += 1;
        }
    };

    var first = Recorder{ .id = 1 };
    var second = Recorder{ .id = 2 };

    var pipeline = try init(std.testing.allocator, .{
        .stages = &.{
            .{
                .perception = .{ .Vision = .{} },
                .processor = Processor.initAsProcessor(Ctx, Recorder, &first),
            },
            .{
                .perception = .{ .Vision = .{} },
                .processor = Processor.initAsProcessor(Ctx, Recorder, &second),
                .depends_on = &.{0},
            },
        },
    });
    defer pipeline.deinit();

    var ctx = Ctx{};
    try pipeline.tick(&ctx, .{
        .data = "frame",
        .width = 1,
        .height = 1,
        .fmt = .JPEG,
    });

    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, &ctx.calls);
}

test "pipeline rejects forward dependencies" {
    var noop = struct {
        pub fn process(_: *@This(), _: *void, _: Frame) !void {}
    }{};

    try std.testing.expectError(error.StageDependencyMustPrecedeConsumer, init(std.testing.allocator, .{
        .stages = &.{
            .{
                .perception = .{ .Vision = .{} },
                .processor = Processor.initAsProcessor(void, @TypeOf(noop), &noop),
                .depends_on = &.{1},
            },
            .{
                .perception = .{ .Vision = .{} },
                .processor = Processor.initAsProcessor(void, @TypeOf(noop), &noop),
            },
        },
    }));
}
