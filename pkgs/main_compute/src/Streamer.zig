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
    const stream = std.net.Stream{ .handle = conn_fd };
    defer stream.close();

    var used: usize = 0;
    while (true) {
        if (used >= line_buf.len) return error.LineTooLong;
        const n = try stream.read(line_buf[used..]);
        if (n == 0) break;
        used += n;

        var start: usize = 0;
        while (true) {
            const rel = std.mem.indexOfScalar(u8, line_buf[start..used], '\n') orelse break;
            const end = start + rel;
            on_message(self.allocator, ctx, line_buf[start..end]) catch |e| {
                log.err("Error deserializing incoming message: {any}\n", .{e});
            };
            start = end + 1;
        }

        if (start == 0) continue;
        const remaining = used - start;
        std.mem.copyForwards(u8, line_buf[0..remaining], line_buf[start..used]);
        used = remaining;
    }
}
