//! This is a processor for bottlecap

const std = @import("std");
const Allocator = std.mem.Allocator;

const pp = @import("pp");
const Frame = pp.Frame;
const oz = @import("openzv");
const PipelineCtx = @import("root").PipelineCtx;

const Self = @This();

/// This function is needed as per [pp.Processor]
pub fn process(ctx: *PipelineCtx, frame: Frame) !void {
    const data = frame.data;
    const width = frame.width;
    const height = frame.height;
    const fmt = frame.fmt;
}
