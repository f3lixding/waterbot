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

pub const PerceptionKind = enum { Vision, Lidar };

pub const PerceptionSpec = union(PerceptionKind) {
    Vision: struct {},
    Lidar: struct {},
};

pub const Pipeline = @import("Pipeline.zig");
pub const Processor = @import("Processor.zig");
pub const VideoStreamer = @import("video_feed.zig").VideoStreamer;

test {
    _ = @import("video_feed.zig");
}
