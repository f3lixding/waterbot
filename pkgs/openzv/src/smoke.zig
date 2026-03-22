const std = @import("std");
const openzv = @import("openzv");

pub fn main() !void {
    if (openzv.opencvVersionMajor() < 4) {
        return error.UnexpectedOpenCvVersion;
    }

    const input = [_]u8{
        0, 0, 255,
        255, 255, 255,
    };
    var output = [_]u8{ 0, 0 };

    try openzv.bgrToGray(&input, 2, 1, &output);

    if (!std.mem.eql(u8, &output, &.{ 76, 255 })) {
        return error.UnexpectedGrayOutput;
    }
}
