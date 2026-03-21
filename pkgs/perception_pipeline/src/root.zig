pub const Frame = struct {
    data: []const u8,
    width: u32,
    height: u32,
    fmt: PixelFormat,
};

pub const PixelFormat = enum {
    JPEG,
    YUYV,
};

test {
    _ = @import("video_feed.zig");
}
