const std = @import("std");

const Self = @This();

fd: i32,
addr: std.net.Address,
allocator: std.mem.Allocator,

const log = std.log.scoped(.streamer);

pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    const addr = try std.net.Address.initUnix(path);

    try std.posix.bind(fd, &addr.any, addr.getOsSockLen());
    try std.posix.listen(fd, 5);

    return .{
        .fd = fd,
        .addr = addr,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    std.posix.close(self.fd);
}

pub fn listenAndExecute(
    self: Self,
    line_buf: []u8,
    ctx: ?*anyopaque,
    on_message: fn (std.mem.Allocator, ?*anyopaque, []const u8) anyerror!void,
) !void {
    const conn_fd = try std.posix.accept(self.fd, null, null, 0);
    const file = std.fs.File{ .handle = conn_fd };
    defer file.close();

    var file_reader = file.readerStreaming(line_buf);
    const reader = &file_reader.interface;
    while (true) {
        const msg = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.LineTooLong,
            else => return err,
        } orelse break;

        on_message(self.allocator, ctx, msg) catch |e| {
            log.err("Error deserializing incoming message: {any}\n", .{e});
        };
    }
}
