//! Provides a video feed abstraction for downstream perception code.
//!
//! This module is intended to wrap the Linux V4L2 capture API exposed through
//! `linux/videodev2.h`. The implementation flow for a USB webcam is:
//!
//! 1. Open the device node, usually `/dev/video0`, with `open(..., O_RDWR)`.
//! 2. Query device capabilities with `VIDIOC_QUERYCAP` and verify that the
//!    device supports `V4L2_CAP_VIDEO_CAPTURE` and `V4L2_CAP_STREAMING`.
//! 3. Negotiate a capture format with `VIDIOC_S_FMT`, typically selecting
//!    width, height, and a pixel format such as `V4L2_PIX_FMT_YUYV`.
//! 4. Request a small ring of kernel-owned frame buffers with
//!    `VIDIOC_REQBUFS` using `V4L2_MEMORY_MMAP`.
//! 5. Inspect each allocated buffer with `VIDIOC_QUERYBUF` and map it into
//!    userspace with `mmap` so captured frame data can be read directly.
//! 6. Queue every mapped buffer with `VIDIOC_QBUF` so the driver can start
//!    filling them with incoming frames.
//! 7. Start the stream with `VIDIOC_STREAMON`.
//! 8. Enter the capture loop:
//!    - Dequeue a filled buffer with `VIDIOC_DQBUF`.
//!    - Read the frame bytes from the mapped memory region.
//!    - Hand the frame to the rest of the perception pipeline.
//!    - Requeue the buffer with `VIDIOC_QBUF` so it can be reused.
//! 9. On shutdown, stop streaming with `VIDIOC_STREAMOFF`, unmap all buffers
//!    with `munmap`, and finally close the device file descriptor.
//!
//! Important notes:
//! - `VIDIOC_S_FMT` is a negotiation step. The driver may change the requested
//!   dimensions or pixel format, so the post-call format struct is the source
//!   of truth.
//! - A frame returned from the device is usually not RGB. For example, YUYV is
//!   a packed YUV format and will need conversion before display or use by
//!   RGB-based processing stages.
//! - `ioctl` calls should generally be retried on `EINTR`.

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("string.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
    @cInclude("linux/videodev2.h");
});
const log = std.log.scoped(.videofeed);
const Frame = @import("root.zig").Frame;
const PixelFormat = @import("root.zig").PixelFormat;

const DEFAULT_DEVICE_NAME: [:0]const u8 = "/dev/video0";
const DEFAULT_PIX_WIDTH: u32 = 640;
const DEFAULT_PIX_HEIGHT: u32 = 480;

const Buffer = struct {
    ptr: [*]u8,
    len: usize,
};

// Helper function for cap exchange
// On unix, a blocking syscall can fail with EINTR, hence the while loop
fn xioctl(fd: c_int, request: c_ulong, arg: ?*anyopaque) !void {
    while (true) {
        const rc = c.ioctl(fd, request, arg);
        if (rc == 0) {
            return;
        }
        const err = std.posix.errno(rc);
        if (err == .INTR) {
            log.info("ioctl interrupted, retrying", .{});
            continue;
        }
        return error.IoctlFailed;
    }
}

/// This struct is _not_ thread safe
pub const VideoStreamer = struct {
    const Self = @This();

    fd: c_int,
    buffers: []Buffer,
    allocator: Allocator,
    is_streaming: bool,
    // TODO: make these customizable
    fmt: PixelFormat = .YUYV,
    width: u32 = DEFAULT_PIX_WIDTH,
    height: u32 = DEFAULT_PIX_HEIGHT,

    pub fn init(allocator: Allocator, device_name: ?[:0]const u8) !Self {
        const dir = device_name orelse DEFAULT_DEVICE_NAME;
        const fd = c.open(dir, c.O_RDWR);
        if (fd < 0) {
            return error.BadDevice;
        }
        errdefer _ = c.close(fd);

        // We need to be zeroing it here otherwise other subfields might not be
        // valid
        var caps: c.struct_v4l2_capability = std.mem.zeroes(c.struct_v4l2_capability);
        try xioctl(fd, c.VIDIOC_QUERYCAP, &caps);

        if ((caps.capabilities & c.V4L2_CAP_VIDEO_CAPTURE) == 0) return error.NoCaptureDevice;
        if ((caps.capabilities & c.V4L2_CAP_STREAMING) == 0) return error.NoStreamingDevice;

        var fmt: c.struct_v4l2_format = std.mem.zeroes(c.struct_v4l2_format);
        fmt.type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        fmt.fmt.pix.width = DEFAULT_PIX_WIDTH;
        fmt.fmt.pix.height = DEFAULT_PIX_HEIGHT;
        fmt.fmt.pix.pixelformat = c.V4L2_PIX_FMT_YUYV;
        fmt.fmt.pix.field = c.V4L2_FIELD_NONE;
        try xioctl(fd, c.VIDIOC_S_FMT, &fmt);

        // Ask the V4L2 driver to allocate a set of capture buffers for streaming
        // We are doing this because these buffers are to be kernal owned (this
        // way we don't have to copy)
        // And also because they are kernal owned we do not have to allocate it
        // in userspace
        var req: c.struct_v4l2_requestbuffers = std.mem.zeroes(c.struct_v4l2_requestbuffers);
        req.count = 4;
        req.type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        req.memory = c.V4L2_MEMORY_MMAP;
        try xioctl(fd, c.VIDIOC_REQBUFS, &req);
        if (req.count < 2) return error.NotEnoughBuffers;

        const buffer_count: usize = req.count;
        var buffers = try allocator.alloc(Buffer, buffer_count);
        var mapped_count: usize = 0;
        errdefer {
            for (buffers[0..mapped_count]) |buffer| {
                _ = c.munmap(@ptrCast(buffer.ptr), buffer.len);
            }
            allocator.free(buffers);
        }

        for (0..buffer_count) |i| {
            var buf: c.struct_v4l2_buffer = std.mem.zeroes(c.struct_v4l2_buffer);
            buf.type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
            buf.memory = c.V4L2_MEMORY_MMAP;
            buf.index = @intCast(i);

            try xioctl(fd, c.VIDIOC_QUERYBUF, &buf);

            const mapped = c.mmap(
                null,
                buf.length,
                c.PROT_READ | c.PROT_WRITE,
                c.MAP_SHARED,
                fd,
                @intCast(buf.m.offset),
            );
            if (mapped == c.MAP_FAILED) return error.MmapFailed;

            buffers[i] = .{
                .ptr = @ptrCast(mapped),
                .len = buf.length,
            };

            mapped_count += 1;
        }

        return .{
            .fd = fd,
            .buffers = buffers,
            .allocator = allocator,
            .is_streaming = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.is_streaming) {
            var buf_type: c.enum_v4l2_buf_type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
            _ = c.ioctl(self.fd, c.VIDIOC_STREAMOFF, &buf_type);
            self.is_streaming = false;
        }

        for (self.buffers) |buffer| {
            _ = c.munmap(@ptrCast(buffer.ptr), buffer.len);
        }

        self.allocator.free(self.buffers);

        const rc = c.close(self.fd);
        if (rc != 0) {
            log.err("video device not closed properly: errcode: {d}", .{rc});
        }

        self.* = undefined;
    }

    pub fn nextFrame(self: *Self) !Frame {
        if (!self.is_streaming) {
            for (0..self.buffers.len) |i| {
                var buf: c.struct_v4l2_buffer = std.mem.zeroes(c.struct_v4l2_buffer);
                buf.type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
                buf.memory = c.V4L2_MEMORY_MMAP;
                buf.index = @intCast(i);

                try xioctl(self.fd, c.VIDIOC_QBUF, &buf);
            }

            var buf_type: c.enum_v4l2_buf_type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
            try xioctl(self.fd, c.VIDIOC_STREAMON, &buf_type);
            self.is_streaming = true;
        }

        var buf: c.struct_v4l2_buffer = std.mem.zeroes(c.struct_v4l2_buffer);
        buf.type = c.V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = c.V4L2_MEMORY_MMAP;

        try xioctl(self.fd, c.VIDIOC_DQBUF, &buf);
        defer xioctl(self.fd, c.VIDIOC_QBUF, &buf) catch |err| {
            log.err("failed to requeue frame buffer {d}: {s}", .{ buf.index, @errorName(err) });
        };

        const data = self.buffers[buf.index].ptr[0..buf.bytesused];

        return .{
            .data = data,
            .width = self.width,
            .height = self.height,
            .fmt = self.fmt,
        };
    }
};

// This test uses real /dev so it would only pass if the machine running the
// test has this device
test "video stream emits bytes" {
    std.fs.cwd().access(DEFAULT_DEVICE_NAME, .{}) catch return error.SkipZigTest;

    var streamer = VideoStreamer.init(std.testing.allocator, null) catch |err| switch (err) {
        error.BadDevice,
        error.NoCaptureDevice,
        error.NoStreamingDevice,
        => return error.SkipZigTest,
        else => return err,
    };
    defer streamer.deinit();

    const total_bytes = (try streamer.nextFrame()).data.len;
    std.debug.print("total bytes: {d}\n", .{total_bytes});
    try std.testing.expect(total_bytes > 0);
}
