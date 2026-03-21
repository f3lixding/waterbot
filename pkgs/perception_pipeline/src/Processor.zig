//! An interface with which processing is done.
//! This is the major extensibility point of the library (since perception wise
//! there isn't much to customize)
//!
//! The high level goals of this interface are the following:
//! - Composable: a processor is supposed to be able to work with another
//!   instance to form a pipeline
//! - Perception agnostic: since the internal logic of the processor is to be
//!   provided by the consumer, it should not concern itself with what is being
//!   processed
const std = @import("std");
const Allocator = std.mem.Allocator;
const Frame = @import("root.zig").Frame;

const Processor = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    process: fn (
        *anyopaque,
        *anyopaque,
        Frame,
    ) anyerror!void,
};

pub fn initAsProcessor(comptime C: type, comptime T: type, ptr: *T) Processor {
    std.debug.assert(@hasDecl(T, "process"));

    return .{
        .ptr = ptr,
        .vtable = &.{
            .process = struct {
                fn call(raw: *anyopaque, ctx: *anyopaque, frame: Frame) anyerror!void {
                    const self: *T = @ptrCast(@alignCast(raw));
                    const ctx_typed: *C = @ptrCast(@alignCast(ctx));
                    self.process(ctx_typed, frame);
                }
            }.call,
        },
    };
}

/// Process the frame and update the context passed
/// If the return is an error it signifies that the Frame should be discarded
pub fn process(self: Processor, ctx: *anyopaque, frame: Frame) !void {
    self.process(ctx, frame);
}
