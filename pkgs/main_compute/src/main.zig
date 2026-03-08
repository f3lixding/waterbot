const std = @import("std");
const main_compute = @import("main_compute");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try main_compute.bufferedPrint();
}
