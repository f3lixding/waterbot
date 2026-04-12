const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ros_prefix = resolvePathOptionFromEnv(
        b,
        b.option([]const u8, "ros-prefix", "Prefix path for ROS 2 headers and libraries"),
        "WATERBOT_ROS_PREFIX",
    );
    const ros_enabled = b.option(bool, "ros-enabled", "Whether ROS 2 headers and libraries should be exposed") orelse (ros_prefix != null);

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

        var include_dir_opened = std.fs.openDirAbsolute(include_dir, .{ .iterate = true }) catch unreachable;
        defer include_dir_opened.close();

        var include_iter = include_dir_opened.iterate();

        var include_roots: std.ArrayList([]const u8) = .empty;
        defer include_roots.deinit(b.allocator);

        include_roots.append(b.allocator, include_dir) catch unreachable;

        while (include_iter.next() catch unreachable) |entry| {
            switch (entry.kind) {
                .directory, .sym_link => {},
                else => continue,
            }

            const to_add = b.pathJoin(&.{ include_dir, entry.name });
            include_roots.append(b.allocator, to_add) catch unreachable;
        }

        const lib_dir = b.pathJoin(&.{ prefix, "lib" });

        for (include_roots.items) |path| {
            mod.addIncludePath(.{ .cwd_relative = path });
        }
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

    const header_smoke = b.addTest(.{
        .name = "ros2_header_smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/header_smoke_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    header_smoke.root_module.addImport("ros2", mod);

    const run_header_smoke = b.addRunArtifact(header_smoke);
    const test_step = b.step("test", "Compile and run the ROS 2 header smoke test");
    test_step.dependOn(&run_header_smoke.step);
}

fn resolvePathOptionFromEnv(
    b: *std.Build,
    provided: ?[]const u8,
    env_name: []const u8,
) ?[]const u8 {
    if (provided) |value| return value;

    const env_value = std.process.getEnvVarOwned(b.allocator, env_name) catch return null;
    defer b.allocator.free(env_value);

    const trimmed = std.mem.trim(u8, env_value, " \t\r\n");
    if (trimmed.len == 0) return null;

    return b.dupe(trimmed);
}
