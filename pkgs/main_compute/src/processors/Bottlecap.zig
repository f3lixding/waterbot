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
const MAX_MASK_LEN: u32 = MAX_WIDTH * MAX_HEIGHT;
const MAX_OUTPUT_BGR_ARR_LEN: u32 = MAX_WIDTH * MAX_HEIGHT * 3;
const MAX_OUTPUT_HSV_ARR_LEN: u32 = MAX_WIDTH * MAX_HEIGHT * 3;

/// This function is needed as per [pp.Processor]
/// We'll have to do here the following:
/// - convert frame
/// - threshold a known color
/// - find the largest blob
/// - report center/radius
pub fn process(_: *Self, ctx: *PipelineCtx, frame: Frame) !void {
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

    // Example red pixels:
    const range = oz.HsvRange{
        .h_min = 0,
        .s_min = 120,
        .v_min = 80,
        .h_max = 10,
        .s_max = 255,
        .v_max = 255,
    };

    const mask_len: usize = @intCast(width * height);
    const exp_output_len: usize = @intCast(mask_len * 3);

    var output_bgr: [MAX_OUTPUT_BGR_ARR_LEN]u8 = undefined;
    var output_hsv: [MAX_OUTPUT_HSV_ARR_LEN]u8 = undefined;
    var mask: [MAX_MASK_LEN]u8 = undefined;
    const min_area: f32 = 50.0;

    const bgr = output_bgr[0..exp_output_len];
    const hsv = output_hsv[0..exp_output_len];
    const mask_view = mask[0..mask_len];

    try oz.yuyvToBgr(data, width, height, bgr);
    try oz.bgrToHsv(bgr, width, height, hsv);
    try oz.hsvInRange(hsv, width, height, range, mask_view);

    const circle = oz.findLargestBlobCircle(mask_view, width, height, min_area) catch |err| switch (err) {
        error.NoBlobFound => {
            ctx.offset_dir = .NotFound;
            return;
        },
        else => return err,
    };
    const center_x = circle.center_x;
    const min_x: f32 = @floatFromInt(width / 3);
    const max_x: f32 = min_x * 2;

    if (center_x >= min_x and center_x <= max_x) {
        ctx.offset_dir = .Center;
    } else if (center_x < min_x) {
        ctx.offset_dir = .Left;
    } else {
        ctx.offset_dir = .Right;
    }
}

test "test bottlecap pos" {
    const allocator = std.testing.allocator;
    // if test is failing because of no file found make sure to run it at package root!
    const image = try std.fs.cwd().openFile("testdata/red_bottlecap_left.yuyv", .{});
    defer image.close();

    const data = try image.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(data);

    const frame = Frame{
        .data = data,
        .width = MAX_WIDTH,
        .height = MAX_HEIGHT,
        .fmt = .YUYV,
    };
    var pp_ctx: PipelineCtx = undefined;

    var processor = Self{};
    processor.process(&pp_ctx, frame) catch unreachable;
    std.debug.assert(pp_ctx.offset_dir == .Left);
}
