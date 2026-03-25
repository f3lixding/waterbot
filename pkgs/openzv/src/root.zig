const std = @import("std");

pub const OpenCvError = error{
    InvalidBuffer,
    NoBlobFound,
    OpenCvFailure,
};

pub const ImageSize = extern struct {
    width: c_int,
    height: c_int,
};

pub const HsvRange = extern struct {
    h_min: u8,
    s_min: u8,
    v_min: u8,
    h_max: u8,
    s_max: u8,
    v_max: u8,
};

pub const BlobCircle = extern struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    area: f32,
};

extern fn openzv_opencv_version_major() callconv(.c) c_int;
extern fn openzv_jpeg_info(
    input_jpeg: [*]const u8,
    input_len: usize,
    output_size: *ImageSize,
) callconv(.c) c_int;
extern fn openzv_decode_jpeg_to_bgr(
    input_jpeg: [*]const u8,
    input_len: usize,
    width: c_int,
    height: c_int,
    output_bgr: [*]u8,
) callconv(.c) c_int;
extern fn openzv_yuyv_to_bgr(
    input_yuyv: [*]const u8,
    width: c_int,
    height: c_int,
    output_bgr: [*]u8,
) callconv(.c) c_int;
extern fn openzv_bgr_to_gray(
    input_bgr: [*]const u8,
    width: c_int,
    height: c_int,
    output_gray: [*]u8,
) callconv(.c) c_int;
extern fn openzv_bgr_to_hsv(
    input_bgr: [*]const u8,
    width: c_int,
    height: c_int,
    output_hsv: [*]u8,
) callconv(.c) c_int;
extern fn openzv_hsv_in_range(
    input_hsv: [*]const u8,
    width: c_int,
    height: c_int,
    range: HsvRange,
    output_mask: [*]u8,
) callconv(.c) c_int;
extern fn openzv_find_largest_blob_circle(
    input_mask: [*]const u8,
    width: c_int,
    height: c_int,
    min_area: f32,
    output_circle: *BlobCircle,
) callconv(.c) c_int;

pub fn opencvVersionMajor() u32 {
    return @intCast(openzv_opencv_version_major());
}

pub fn jpegInfo(input_jpeg: []const u8) OpenCvError!ImageSize {
    if (input_jpeg.len == 0) return error.InvalidBuffer;

    var size: ImageSize = undefined;
    const rc = openzv_jpeg_info(input_jpeg.ptr, input_jpeg.len, &size);
    if (rc != 0) {
        return error.OpenCvFailure;
    }
    return size;
}

pub fn decodeJpegToBgr(
    input_jpeg: []const u8,
    output_bgr: []u8,
) OpenCvError!ImageSize {
    const size = try jpegInfo(input_jpeg);
    const width = std.math.cast(usize, size.width) orelse return error.InvalidBuffer;
    const height = std.math.cast(usize, size.height) orelse return error.InvalidBuffer;
    const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidBuffer;
    const output_len = std.math.mul(usize, pixel_count, 3) catch return error.InvalidBuffer;

    if (output_bgr.len != output_len) {
        return error.InvalidBuffer;
    }

    const rc = openzv_decode_jpeg_to_bgr(
        input_jpeg.ptr,
        input_jpeg.len,
        size.width,
        size.height,
        output_bgr.ptr,
    );
    if (rc != 0) {
        return error.OpenCvFailure;
    }

    return size;
}

pub fn yuyvToBgr(
    input_yuyv: []const u8,
    width: usize,
    height: usize,
    output_bgr: []u8,
) OpenCvError!void {
    const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidBuffer;
    const input_len = std.math.mul(usize, pixel_count, 2) catch return error.InvalidBuffer;
    const output_len = std.math.mul(usize, pixel_count, 3) catch return error.InvalidBuffer;

    if (input_yuyv.len != input_len or output_bgr.len != output_len) {
        return error.InvalidBuffer;
    }

    const rc = openzv_yuyv_to_bgr(
        input_yuyv.ptr,
        std.math.cast(c_int, width) orelse return error.InvalidBuffer,
        std.math.cast(c_int, height) orelse return error.InvalidBuffer,
        output_bgr.ptr,
    );
    if (rc != 0) {
        return error.OpenCvFailure;
    }
}

pub fn bgrToGray(
    input_bgr: []const u8,
    width: usize,
    height: usize,
    output_gray: []u8,
) OpenCvError!void {
    const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidBuffer;
    const input_len = std.math.mul(usize, pixel_count, 3) catch return error.InvalidBuffer;

    if (input_bgr.len != input_len or output_gray.len != pixel_count) {
        return error.InvalidBuffer;
    }

    const rc = openzv_bgr_to_gray(
        input_bgr.ptr,
        std.math.cast(c_int, width) orelse return error.InvalidBuffer,
        std.math.cast(c_int, height) orelse return error.InvalidBuffer,
        output_gray.ptr,
    );
    if (rc != 0) {
        return error.OpenCvFailure;
    }
}

pub fn bgrToHsv(
    input_bgr: []const u8,
    width: usize,
    height: usize,
    output_hsv: []u8,
) OpenCvError!void {
    const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidBuffer;
    const input_len = std.math.mul(usize, pixel_count, 3) catch return error.InvalidBuffer;

    if (input_bgr.len != input_len or output_hsv.len != input_len) {
        return error.InvalidBuffer;
    }

    const rc = openzv_bgr_to_hsv(
        input_bgr.ptr,
        std.math.cast(c_int, width) orelse return error.InvalidBuffer,
        std.math.cast(c_int, height) orelse return error.InvalidBuffer,
        output_hsv.ptr,
    );
    if (rc != 0) {
        return error.OpenCvFailure;
    }
}

pub fn hsvInRange(
    input_hsv: []const u8,
    width: usize,
    height: usize,
    range: HsvRange,
    output_mask: []u8,
) OpenCvError!void {
    const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidBuffer;
    const input_len = std.math.mul(usize, pixel_count, 3) catch return error.InvalidBuffer;

    if (input_hsv.len != input_len or output_mask.len != pixel_count) {
        return error.InvalidBuffer;
    }

    const rc = openzv_hsv_in_range(
        input_hsv.ptr,
        std.math.cast(c_int, width) orelse return error.InvalidBuffer,
        std.math.cast(c_int, height) orelse return error.InvalidBuffer,
        range,
        output_mask.ptr,
    );
    if (rc != 0) {
        return error.OpenCvFailure;
    }
}

pub fn findLargestBlobCircle(
    input_mask: []const u8,
    width: usize,
    height: usize,
    min_area: f32,
) OpenCvError!BlobCircle {
    const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidBuffer;
    if (input_mask.len != pixel_count) {
        return error.InvalidBuffer;
    }

    var circle: BlobCircle = undefined;
    const rc = openzv_find_largest_blob_circle(
        input_mask.ptr,
        std.math.cast(c_int, width) orelse return error.InvalidBuffer,
        std.math.cast(c_int, height) orelse return error.InvalidBuffer,
        min_area,
        &circle,
    );
    return switch (rc) {
        0 => circle,
        1 => error.NoBlobFound,
        else => error.OpenCvFailure,
    };
}

test "rejects short input buffer" {
    const input = [_]u8{ 0, 0, 255 };
    var output = [_]u8{0};

    try std.testing.expectError(error.InvalidBuffer, bgrToGray(&input, 2, 1, &output));
}

test "rejects short output buffer" {
    const input = [_]u8{
        0, 0, 255,
        255, 255, 255,
    };
    var output = [_]u8{0};

    try std.testing.expectError(error.InvalidBuffer, bgrToGray(&input, 2, 1, &output));
}

test "rejects short YUYV buffer" {
    const input = [_]u8{ 16, 128 };
    var output = [_]u8{ 0, 0, 0, 0, 0, 0 };

    try std.testing.expectError(error.InvalidBuffer, yuyvToBgr(&input, 2, 1, &output));
}

test "finds blob in binary mask" {
    const mask = [_]u8{
        0,   0,   0,   0,
        0, 255, 255,   0,
        0, 255, 255,   0,
        0,   0,   0,   0,
    };

    const circle = try findLargestBlobCircle(&mask, 4, 4, 1.0);
    try std.testing.expect(circle.radius > 0.0);
    try std.testing.expect(circle.area >= 1.0);
}
