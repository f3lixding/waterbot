const std = @import("std");

pub const OpenCvError = error{
    InvalidBuffer,
    OpenCvFailure,
};

extern fn openzv_opencv_version_major() callconv(.c) c_int;
extern fn openzv_bgr_to_gray(
    input_bgr: [*]const u8,
    width: c_int,
    height: c_int,
    output_gray: [*]u8,
) callconv(.c) c_int;

pub fn opencvVersionMajor() u32 {
    return @intCast(openzv_opencv_version_major());
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
