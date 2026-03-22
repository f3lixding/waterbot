const std = @import("std");

pub const OpenCvError = error{
    InvalidBuffer,
    OpenCvFailure,
    BridgeLoadFailed,
    BridgeSymbolMissing,
};

const VersionFn = *const fn () callconv(.c) c_int;
const GrayFn = *const fn (
    input_bgr: [*]const u8,
    width: c_int,
    height: c_int,
    output_gray: [*]u8,
) callconv(.c) c_int;

const Bridge = struct {
    lib: std.DynLib,
    version_major: VersionFn,
    bgr_to_gray: GrayFn,
};

var bridge: ?Bridge = null;

fn getBridge() OpenCvError!*Bridge {
    if (bridge == null) {
        var lib = std.DynLib.open("libopenzv_bridge.so") catch return error.BridgeLoadFailed;
        const version_fn = lib.lookup(VersionFn, "openzv_opencv_version_major") orelse
            return error.BridgeSymbolMissing;
        const gray_fn = lib.lookup(GrayFn, "openzv_bgr_to_gray") orelse
            return error.BridgeSymbolMissing;
        bridge = .{
            .lib = lib,
            .version_major = version_fn,
            .bgr_to_gray = gray_fn,
        };
    }
    return &bridge.?;
}

pub fn opencvVersionMajor() OpenCvError!u32 {
    const loaded = try getBridge();
    return @intCast(loaded.version_major());
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

    const loaded = try getBridge();
    const rc = loaded.bgr_to_gray(
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
