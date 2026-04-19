//! This is a processor for bottlecap

const std = @import("std");
const Allocator = std.mem.Allocator;

const logging = std.log.scoped(.bottlecap);

const pp = @import("pp");
const Frame = pp.Frame;
const oz = @import("openzv");
const PipelineCtx = @import("../main.zig").PipelineCtx;

const Self = @This();
// We will only support up to 1080p for now
const MAX_WIDTH: u32 = 1920;
const MAX_HEIGHT: u32 = 1080;
const MIN_ABSOLUTE_BLOB_AREA: usize = 25;
const MIN_RELATIVE_BLOB_AREA_DIVISOR: usize = 12_000;
const CENTER_BAND_START: f32 = 0.40;
const CENTER_BAND_END: f32 = 0.60;

const low_red_range = oz.HsvRange{
    .h_min = 0,
    .s_min = 120,
    .v_min = 80,
    .h_max = 10,
    .s_max = 255,
    .v_max = 255,
};

const high_red_range = oz.HsvRange{
    .h_min = 170,
    .s_min = 120,
    .v_min = 80,
    .h_max = 179,
    .s_max = 255,
    .v_max = 255,
};

scratch: Scratch,

const Scratch = struct {
    allocator: Allocator,
    bgr: ?[]u8 = null,
    hsv: ?[]u8 = null,
    mask: ?[]u8 = null,
    wrapped_mask: ?[]u8 = null,

    fn init(allocator: Allocator) Scratch {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Scratch) void {
        if (self.bgr) |buffer| self.allocator.free(buffer);
        if (self.hsv) |buffer| self.allocator.free(buffer);
        if (self.mask) |buffer| self.allocator.free(buffer);
        if (self.wrapped_mask) |buffer| self.allocator.free(buffer);
        self.* = undefined;
    }

    fn ensureCapacity(self: *Scratch, pixel_count: usize) !void {
        const color_len = try std.math.mul(usize, pixel_count, 3);
        try ensureBufferCapacity(self.allocator, &self.bgr, color_len);
        try ensureBufferCapacity(self.allocator, &self.hsv, color_len);
        try ensureBufferCapacity(self.allocator, &self.mask, pixel_count);
        try ensureBufferCapacity(self.allocator, &self.wrapped_mask, pixel_count);
    }
};

pub fn init(allocator: Allocator) Self {
    return .{
        .scratch = Scratch.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.scratch.deinit();
    self.* = undefined;
}

/// This function is needed as per [pp.Processor]
/// We'll have to do here the following:
/// - convert frame
/// - threshold a known color
/// - find the largest blob
/// - report center/radius
pub fn process(self: *Self, ctx: *PipelineCtx, frame: Frame) !void {
    const data = frame.data;
    const width = frame.width;
    const height = frame.height;
    const fmt = frame.fmt;

    // TODO: support other format
    if (fmt != .YUYV) {
        return error.UnsupportedFmt;
    }
    if (width > MAX_WIDTH or height > MAX_HEIGHT) {
        return error.ImageTooBig;
    }

    const pixel_count = try std.math.mul(usize, width, height);
    const exp_output_len = try std.math.mul(usize, pixel_count, 3);
    const min_area = minimumBlobArea(width, height);

    try self.scratch.ensureCapacity(pixel_count);

    const bgr = self.scratch.bgr.?[0..exp_output_len];
    const hsv = self.scratch.hsv.?[0..exp_output_len];
    const mask_view = self.scratch.mask.?[0..pixel_count];
    const wrapped_mask_view = self.scratch.wrapped_mask.?[0..pixel_count];

    try oz.yuyvToBgr(data, width, height, bgr);
    try oz.bgrToHsv(bgr, width, height, hsv);
    try oz.hsvInRange(hsv, width, height, low_red_range, mask_view);
    try oz.hsvInRange(hsv, width, height, high_red_range, wrapped_mask_view);
    combineMasks(mask_view, wrapped_mask_view);

    const circle = oz.findLargestBlobCircle(mask_view, width, height, min_area) catch |err| switch (err) {
        error.NoBlobFound => {
            logging.debug("no bottlecap blob found above area threshold {d:.1}", .{min_area});
            ctx.offset_dir = .NotFound;
            return;
        },
        else => return err,
    };
    logging.debug(
        "bottlecap blob center_x={d:.1} center_y={d:.1} area={d:.1}",
        .{ circle.center_x, circle.center_y, circle.area },
    );
    ctx.offset_dir = directionForCenterX(width, circle.center_x);
}

fn ensureBufferCapacity(allocator: Allocator, buffer: *?[]u8, needed: usize) !void {
    if (buffer.*) |existing| {
        if (existing.len >= needed) return;
        buffer.* = try allocator.realloc(existing, needed);
        return;
    }

    buffer.* = try allocator.alloc(u8, needed);
}

fn combineMasks(dst: []u8, src: []const u8) void {
    std.debug.assert(dst.len == src.len);

    for (dst, src) |*out, in| {
        out.* |= in;
    }
}

fn minimumBlobArea(width: u32, height: u32) f32 {
    const pixel_count = std.math.mul(usize, width, height) catch unreachable;
    const scaled = pixel_count / MIN_RELATIVE_BLOB_AREA_DIVISOR;
    const min_area = @max(MIN_ABSOLUTE_BLOB_AREA, scaled);
    return @floatFromInt(min_area);
}

fn directionForCenterX(width: u32, center_x: f32) PipelineCtx.Dir {
    const frame_width: f32 = @floatFromInt(width);
    const min_center_x = frame_width * CENTER_BAND_START;
    const max_center_x = frame_width * CENTER_BAND_END;

    if (center_x < min_center_x) return .Left;
    if (center_x > max_center_x) return .Right;
    return .Center;
}

test "test bottlecap pos" {
    const allocator = std.testing.allocator;
    // if test is failing because of no file found make sure to run it at package root!
    const image = try std.Io.Dir.cwd().openFile(std.testing.io, "testdata/red_bottlecap_left.yuyv", .{});
    defer image.close(std.testing.io);

    var reader_buf: [4096]u8 = undefined;
    var image_reader = image.readerStreaming(std.testing.io, &reader_buf);
    const data = try image_reader.interface.allocRemaining(allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(data);

    const frame = Frame{
        .data = data,
        .width = MAX_WIDTH,
        .height = MAX_HEIGHT,
        .fmt = .YUYV,
    };
    var pp_ctx: PipelineCtx = undefined;

    var processor = Self.init(allocator);
    defer processor.deinit();
    processor.process(&pp_ctx, frame) catch unreachable;
    std.debug.assert(pp_ctx.offset_dir == .Left);
}

test "directionForCenterX uses a centered deadband" {
    try std.testing.expectEqual(PipelineCtx.Dir.Left, directionForCenterX(100, 39.9));
    try std.testing.expectEqual(PipelineCtx.Dir.Center, directionForCenterX(100, 40.0));
    try std.testing.expectEqual(PipelineCtx.Dir.Center, directionForCenterX(100, 60.0));
    try std.testing.expectEqual(PipelineCtx.Dir.Right, directionForCenterX(100, 60.1));
}

test "minimumBlobArea scales with frame size" {
    try std.testing.expectEqual(@as(f32, 25), minimumBlobArea(320, 240));
    try std.testing.expectEqual(@as(f32, 172), minimumBlobArea(MAX_WIDTH, MAX_HEIGHT));
}

test "scratch buffers grow once and do not shrink for smaller frames" {
    var scratch = Scratch.init(std.testing.allocator);
    defer scratch.deinit();

    try scratch.ensureCapacity(64);
    const initial_bgr_len = scratch.bgr.?.len;
    const initial_mask_len = scratch.mask.?.len;

    try std.testing.expectEqual(@as(usize, 192), initial_bgr_len);
    try std.testing.expectEqual(@as(usize, 64), initial_mask_len);

    try scratch.ensureCapacity(32);

    try std.testing.expectEqual(initial_bgr_len, scratch.bgr.?.len);
    try std.testing.expectEqual(initial_mask_len, scratch.mask.?.len);
}
