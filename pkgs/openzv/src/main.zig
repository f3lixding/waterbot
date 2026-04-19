const std = @import("std");
const openzv = @import("openzv");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("OpenCV major version: {}\n", .{openzv.opencvVersionMajor()});
    try stdout.flush();
}
