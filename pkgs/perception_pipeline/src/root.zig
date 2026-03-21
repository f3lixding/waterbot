const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
    @cInclude("linux/videodev2.h");
});

test {
    _ = @import("video_feed.zig");
    const caps: c.struct_v4l2_capability = std.mem.zeroes(c.struct_v4l2_capability);

    try std.testing.expect(c.O_RDWR != 0);
    try std.testing.expect(c.VIDIOC_QUERYCAP != 0);
    try std.testing.expect(@sizeOf(@TypeOf(caps)) > 0);
}
