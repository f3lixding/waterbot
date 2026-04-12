const ros2 = @import("ros2");

test "ros2 c import resolves headers when enabled" {
    if (ros2.available) {
        _ = ros2.c.rcl_get_zero_initialized_context;
        _ = ros2.c.rcl_get_zero_initialized_init_options;
        _ = ros2.c.rcutils_get_default_allocator;
        _ = ros2.c.rosidl_runtime_c__String;
    }
}
