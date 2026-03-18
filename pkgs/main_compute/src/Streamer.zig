const std = @import("std");

const Self = @This();

const MessageHandler = *const fn (std.mem.Allocator, ?*anyopaque, []const u8) anyerror!void;

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

const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    conn_fd: i32,
    user_ctx: ?*anyopaque,
    on_message: MessageHandler,

    fn run(self: *ConnectionContext) void {
        defer self.allocator.destroy(self);
        handleConnection(self.allocator, self.conn_fd, self.user_ctx, self.on_message) catch |err| {
            log.err("Connection handler failed: {any}\n", .{err});
        };
    }
};

pub fn serve(
    self: Self,
    ctx: ?*anyopaque,
    on_message: MessageHandler,
) !void {
    while (true) {
        const conn_fd = try std.posix.accept(self.fd, null, null, 0);
        errdefer std.posix.close(conn_fd);

        const connection = try self.allocator.create(ConnectionContext);
        connection.* = .{
            .allocator = self.allocator,
            .conn_fd = conn_fd,
            .user_ctx = ctx,
            .on_message = on_message,
        };

        const thread = try std.Thread.spawn(.{}, ConnectionContext.run, .{connection});
        thread.detach();
    }
}

fn handleConnection(
    allocator: std.mem.Allocator,
    conn_fd: i32,
    ctx: ?*anyopaque,
    on_message: MessageHandler,
) !void {
    const file = std.fs.File{ .handle = conn_fd };
    defer file.close();

    var line_buf: [4096]u8 = undefined;
    var file_reader = file.readerStreaming(&line_buf);
    const reader = &file_reader.interface;
    while (true) {
        const msg = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.LineTooLong,
            else => return err,
        } orelse break;

        on_message(allocator, ctx, msg) catch |e| {
            log.err("Error deserializing incoming message: {any}\n", .{e});
        };
    }
}
