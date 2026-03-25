const std = @import("std");
const openzv = @import("openzv");

pub fn main() !void {
    if (openzv.opencvVersionMajor() < 4) {
        return error.UnexpectedOpenCvVersion;
    }

    const bgr_input = [_]u8{
        0, 0, 255,
        255, 255, 255,
    };
    var gray_output = [_]u8{ 0, 0 };
    var hsv_output = [_]u8{0} ** 6;
    var mask_output = [_]u8{ 0, 0 };

    try openzv.bgrToGray(&bgr_input, 2, 1, &gray_output);
    try openzv.bgrToHsv(&bgr_input, 2, 1, &hsv_output);
    try openzv.hsvInRange(&hsv_output, 2, 1, .{
        .h_min = 0,
        .s_min = 200,
        .v_min = 200,
        .h_max = 10,
        .s_max = 255,
        .v_max = 255,
    }, &mask_output);

    if (!std.mem.eql(u8, &gray_output, &.{ 76, 255 })) {
        return error.UnexpectedGrayOutput;
    }
    if (mask_output[0] == 0 or mask_output[1] != 0) {
        return error.UnexpectedMaskOutput;
    }
}
