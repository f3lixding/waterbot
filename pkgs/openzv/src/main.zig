const std = @import("std");
const openzv = @import("openzv");

pub fn main() !void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("OpenCV major version: {}\n", .{try openzv.opencvVersionMajor()});
    try stdout.flush();
}
