const build_options = @import("build_options");

pub const available = build_options.ros_enabled;

pub const c = if (available)
    @cImport({
        @cInclude("rcl/rcl.h");
        @cInclude("rcl/error_handling.h");
        @cInclude("rcutils/allocator.h");
        @cInclude("rcutils/error_handling.h");
        @cInclude("rosidl_runtime_c/string.h");
    })
else
    struct {};
