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
const VideoStreamer = @import("video_feed.zig").VideoStreamer;

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
video_streamer: ?VideoStreamer,

pub fn init(alloc: Allocator, config: PipelineConfig) !Self {
    var video_streamer: ?VideoStreamer = null;
    var stages = try alloc.alloc(Stage, config.stages.len);
    errdefer alloc.free(stages);
    var owned_dep_count: usize = 0;
    errdefer {
        for (stages[0..owned_dep_count]) |stage| {
            alloc.free(stage.depends_on);
        }
        if (video_streamer) |*vs| {
            vs.deinit();
        }
    }

    for (config.stages, 0..) |stage, i| {
        stages[i] = stage;
        stages[i].depends_on = try alloc.dupe(usize, stage.depends_on);
        owned_dep_count = i + 1;

        if (stage.perception == .Vision) {
            if (video_streamer == null) {
                video_streamer = try VideoStreamer.init(alloc, null);
            }
        }
    }

    try validateStages(stages);

    return .{
        .allocator = alloc,
        .stages = stages,
        .video_streamer = video_streamer,
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

pub fn tick(self: *Self, ctx: *anyopaque) !void {
    for (self.stages) |stage| {
        const frame = blk: {
            switch (stage.perception) {
                // TODO: make use of the spec
                .Vision => {
                    if (self.video_streamer) |*vs| {
                        break :blk try vs.nextFrame();
                    } else return error.MissingVideoStreamer;
                },
                else => return error.NotYetSupported,
            }
        };
        try stage.processor.process(ctx, frame);
    }
}

test "pipeline tick fails when a vision stage has no streamer" {
    const Ctx = struct {};

    const Recorder = struct {
        pub fn process(_: *@This(), _: *Ctx, _: Frame) !void {}
    };

    var recorder = Recorder{};
    var stages = [_]Stage{
        .{
            .perception = .{ .Vision = .{} },
            .processor = Processor.initAsProcessor(Ctx, Recorder, &recorder),
        },
    };
    var pipeline = Self{
        .allocator = std.testing.allocator,
        .stages = stages[0..],
        .video_streamer = null,
    };

    var ctx = Ctx{};
    try std.testing.expectError(error.MissingVideoStreamer, pipeline.tick(&ctx));
}

test "pipeline rejects forward dependencies" {
    var noop = struct {
        pub fn process(_: *@This(), _: *void, _: Frame) !void {}
    }{};

    try std.testing.expectError(error.StageDependencyMustPrecedeConsumer, validateStages(&.{
        .{
            .perception = .{ .Vision = .{} },
            .processor = Processor.initAsProcessor(void, @TypeOf(noop), &noop),
            .depends_on = &.{1},
        },
        .{
            .perception = .{ .Vision = .{} },
            .processor = Processor.initAsProcessor(void, @TypeOf(noop), &noop),
        },
    }));
}
