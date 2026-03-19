const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pp = b.addModule("pp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    pp.linkSystemLibrary("v4l2", .{ .preferred_link_mode = .static });

    const test_comp = b.addTest(.{
        .root_module = pp,
    });

    const test_step = b.step("test", "runs tests");
    const test_run = b.addRunArtifact(test_comp);
    test_step.dependOn(&test_run.step);
}
