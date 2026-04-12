const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ros_prefix = b.option([]const u8, "ros-prefix", "Prefix path for ROS 2 headers and libraries");
    const ros_enabled = b.option(bool, "ros-enabled", "Whether ROS 2 headers and libraries should be exposed") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "ros_enabled", ros_enabled);

    const mod = b.addModule("ros2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addOptions("build_options", options);

    if (ros_enabled) {
        const prefix = ros_prefix orelse @panic("ros-enabled requires ros-prefix");
        const include_dir = b.pathJoin(&.{ prefix, "include" });
        const lib_dir = b.pathJoin(&.{ prefix, "lib" });

        mod.addIncludePath(.{ .cwd_relative = include_dir });
        mod.addLibraryPath(.{ .cwd_relative = lib_dir });
        mod.addRPath(.{ .cwd_relative = lib_dir });

        inline for ([_][]const u8{
            "rcl",
            "rcutils",
            "rosidl_runtime_c",
        }) |lib_name| {
            mod.linkSystemLibrary(lib_name, .{
                .needed = true,
                .preferred_link_mode = .dynamic,
                .use_pkg_config = .no,
            });
        }
    }
}
