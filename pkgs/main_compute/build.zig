const std = @import("std");

const SharedDeps = struct {
    import_name: []const u8,
    module_name: []const u8,
    dep: *std.Build.Dependency,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const shared: []const SharedDeps = &[_]SharedDeps{
        .{ .import_name = "httpz", .module_name = "httpz", .dep = httpz },
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

    b.installArtifact(test_bin);
}

fn addSharedDeps(c: *std.Build.Step.Compile, deps: []const SharedDeps) void {
    for (deps) |d| {
        c.root_module.addImport(d.import_name, d.dep.module(d.module_name));
    }
}
