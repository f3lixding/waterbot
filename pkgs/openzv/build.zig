const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opencv_prefix_option = b.option(
        []const u8,
        "opencv-prefix",
        "Prefix path for OpenCV headers and libraries",
    );
    const opencv_prefix = resolveOpenCvPrefix(b, opencv_prefix_option);
    const cxx_compiler = b.option(
        []const u8,
        "cxx-compiler",
        "Path to the C++ compiler used to build the OpenCV bridge",
    ) orelse "c++";
    const ldso_path = b.option(
        []const u8,
        "ldso-path",
        "Absolute path to the dynamic linker used for installed smoke binaries",
    );
    const libstdcpp_dir = b.option(
        []const u8,
        "libstdcpp-dir",
        "Directory containing libstdc++.so for the bridge runtime",
    );

    const mod = b.addModule("openzv", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bridge_lib = buildBridgeLibrary(b, cxx_compiler, opencv_prefix, libstdcpp_dir);
    const install_bridge = b.addInstallFile(bridge_lib, "lib/libopenzv_bridge.so");
    b.getInstallStep().dependOn(&install_bridge.step);

    const exe = b.addExecutable(.{
        .name = "openzv-info",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "openzv", .module = mod },
            },
        }),
    });
    linkBridge(b, exe, opencv_prefix, libstdcpp_dir, bridge_lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Print the linked OpenCV major version");
    run_step.dependOn(&run_cmd.step);

    const smoke = b.addExecutable(.{
        .name = "openzv-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/smoke.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "openzv", .module = mod },
            },
        }),
    });
    linkBridge(b, smoke, opencv_prefix, libstdcpp_dir, bridge_lib);
    b.installArtifact(smoke);

    const smoke_step = b.step("smoke", "Run the Zig/OpenCV smoke test");
    const installed_smoke = b.getInstallPath(.bin, "openzv-smoke");
    if (ldso_path) |interp| {
        const run_smoke = b.addSystemCommand(&.{ interp, installed_smoke });
        run_smoke.step.dependOn(b.getInstallStep());
        smoke_step.dependOn(&run_smoke.step);
    } else {
        const smoke_run = b.addRunArtifact(smoke);
        smoke_run.step.dependOn(b.getInstallStep());
        smoke_step.dependOn(&smoke_run.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn resolveOpenCvPrefix(b: *std.Build, provided: ?[]const u8) ?[]const u8 {
    if (provided) |prefix| return prefix;

    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "pkg-config", "--variable=prefix", "opencv4" },
    }) catch return null;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return null,
        else => return null,
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    return b.dupe(trimmed);
}

fn buildBridgeLibrary(
    b: *std.Build,
    cxx_compiler: []const u8,
    opencv_prefix: ?[]const u8,
    libstdcpp_dir: ?[]const u8,
) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{ cxx_compiler });
    cmd.addArgs(&.{ "-std=c++17", "-shared", "-fPIC" });
    cmd.addFileArg(b.path("src/wrapper.cpp"));

    if (opencv_prefix) |prefix| {
        const include_dir = b.pathJoin(&.{ prefix, "include", "opencv4" });
        const lib_dir = b.pathJoin(&.{ prefix, "lib" });
        const rpath = if (libstdcpp_dir) |cpp_dir|
            b.fmt("{s}:{s}", .{ lib_dir, cpp_dir })
        else
            lib_dir;
        cmd.addArgs(&.{ "-I", include_dir });
        cmd.addArgs(&.{ "-L", lib_dir });
        cmd.addArg(b.fmt("-Wl,-rpath,{s}", .{rpath}));
        cmd.addArgs(&.{ "-lopencv_core", "-lopencv_imgproc" });
    }

    if (libstdcpp_dir) |dir| {
        cmd.addArgs(&.{ "-L", dir });
    }

    return cmd.addPrefixedOutputFileArg("-o", "libopenzv_bridge.so");
}

fn linkBridge(
    b: *std.Build,
    c: *std.Build.Step.Compile,
    opencv_prefix: ?[]const u8,
    libstdcpp_dir: ?[]const u8,
    _: std.Build.LazyPath,
) void {
    c.linkLibC();
    c.root_module.addRPathSpecial("$ORIGIN/../lib");

    if (opencv_prefix) |prefix| {
        const lib_dir = b.pathJoin(&.{ prefix, "lib" });
        c.root_module.addRPath(.{ .cwd_relative = lib_dir });
    }

    if (libstdcpp_dir) |dir| {
        c.root_module.addRPath(.{ .cwd_relative = dir });
    }
}
