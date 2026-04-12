const std = @import("std");

const SharedDeps = struct {
    import_name: []const u8,
    module_name: []const u8,
    dep: *std.Build.Dependency,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gpiod_prefix = b.option([]const u8, "gpiod-prefix", "Prefix path for libgpiod headers and libraries");
    const opencv_prefix = b.option([]const u8, "opencv-prefix", "Prefix path for OpenCV headers and libraries");
    const cxx_compiler = b.option([]const u8, "cxx-compiler", "Path to the C++ compiler used to build the OpenCV bridge");
    const libstdcpp_dir = b.option([]const u8, "libstdcpp-dir", "Directory containing libstdc++.so for the OpenCV bridge runtime");
    const ros_prefix = resolvePathOptionFromEnv(b, b.option([]const u8, "ros-prefix", "Prefix path for ROS 2 headers and libraries"), "WATERBOT_ROS_PREFIX");

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const pp = b.dependency("perception_pipeline", .{
        .target = target,
        .optimize = optimize,
    });
    const openzv = b.dependency("openzv", .{
        .target = target,
        .optimize = optimize,
        .@"opencv-prefix" = opencv_prefix,
        .@"cxx-compiler" = cxx_compiler,
        .@"libstdcpp-dir" = libstdcpp_dir,
    });
    const ros2 = b.dependency("ros2", .{
        .target = target,
        .optimize = optimize,
        .@"ros-prefix" = ros_prefix,
        .@"ros-enabled" = ros_prefix != null,
    });
    const openzv_bridge = openzv.namedLazyPath("openzv_bridge");
    const install_openzv_bridge = b.addInstallFile(openzv_bridge, "lib/libopenzv_bridge.so");
    b.getInstallStep().dependOn(&install_openzv_bridge.step);

    const shared: []const SharedDeps = &[_]SharedDeps{
        .{ .import_name = "httpz", .module_name = "httpz", .dep = httpz },
        .{ .import_name = "openzv", .module_name = "openzv", .dep = openzv },
        .{ .import_name = "pp", .module_name = "pp", .dep = pp },
        .{ .import_name = "ros2", .module_name = "ros2", .dep = ros2 },
    };

    const main_bin = b.addExecutable(.{
        .name = "main_compute",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    addSharedDeps(main_bin, shared);
    linkGpiod(b, main_bin, gpiod_prefix);
    linkOpenzvBridge(main_bin, openzv_bridge);

    b.installArtifact(main_bin);

    // This is to offer an easy way to test the http server
    const test_bin = b.addExecutable(.{
        .name = "test_bin",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/Server.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    addSharedDeps(test_bin, shared);
    linkGpiod(b, test_bin, gpiod_prefix);
    linkOpenzvBridge(test_bin, openzv_bridge);

    b.installArtifact(test_bin);

    // Tests
    const test_entry = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    addSharedDeps(test_entry, shared);
    linkGpiod(b, test_entry, gpiod_prefix);
    linkOpenzvBridge(test_entry, openzv_bridge);

    const test_run = b.addRunArtifact(test_entry);
    const test_step = b.step("test", "runs tests");
    test_step.dependOn(&test_run.step);
}

fn addSharedDeps(c: *std.Build.Step.Compile, deps: []const SharedDeps) void {
    for (deps) |d| {
        c.root_module.addImport(d.import_name, d.dep.module(d.module_name));
    }
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

fn linkOpenzvBridge(c: *std.Build.Step.Compile, bridge_lib: std.Build.LazyPath) void {
    c.root_module.addLibraryPath(bridge_lib.dirname());
    c.root_module.addRPathSpecial("$ORIGIN/../lib");
    c.root_module.linkSystemLibrary("openzv_bridge", .{
        .needed = true,
        .preferred_link_mode = .dynamic,
        .use_pkg_config = .no,
    });
}

/// A special function is needed for this. We needed to namespace the header
/// files as well as actual lib file in accordance to their target platform.
/// Otherwise we would run into linking problem and unresolved glibc symbols
/// (which would fail the compilation as well)
/// The option of prefix is passed in from flake.nix
fn linkGpiod(
    b: *std.Build,
    c: *std.Build.Step.Compile,
    gpiod_prefix: ?[]const u8,
) void {
    c.linkLibC();

    if (gpiod_prefix) |prefix| {
        c.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "include" }) });
        c.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "lib" }) });
    }

    c.linker_allow_shlib_undefined = true;
    c.root_module.linkSystemLibrary("gpiod", .{ .preferred_link_mode = .static });
}
