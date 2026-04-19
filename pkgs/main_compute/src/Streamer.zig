const std = @import("std");

const Self = @This();

const MessageHandler = *const fn (std.mem.Allocator, ?*anyopaque, []const u8) anyerror!void;

server: std.Io.net.Server,
allocator: std.mem.Allocator,
io: std.Io,

const log = std.log.scoped(.streamer);

pub fn init(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Self {
    const addr = try std.Io.net.UnixAddress.init(path);
    const server = try addr.listen(io, .{});

    return .{
        .server = server,
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *Self) void {
    self.server.deinit(self.io);
}

const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    io: std.Io,
    user_ctx: ?*anyopaque,
    on_message: MessageHandler,

    fn run(self: *ConnectionContext) void {
        defer self.allocator.destroy(self);
        handleConnection(self.allocator, self.io, self.stream, self.user_ctx, self.on_message) catch |err| {
            log.err("Connection handler failed: {any}\n", .{err});
        };
    }
};

pub fn serve(
    self: Self,
    ctx: ?*anyopaque,
    on_message: MessageHandler,
) !void {
    var server = self.server;

    while (true) {
        const stream = try server.accept(self.io);
        errdefer stream.close(self.io);

        log.info("connection accepted\n", .{});

        const connection = try self.allocator.create(ConnectionContext);
        connection.* = .{
            .allocator = self.allocator,
            .stream = stream,
            .io = self.io,
            .user_ctx = ctx,
            .on_message = on_message,
        };

        const thread = try std.Thread.spawn(.{}, ConnectionContext.run, .{connection});
        thread.detach();
    }
}

fn handleConnection(
    allocator: std.mem.Allocator,
    io: std.Io,
    stream: std.Io.net.Stream,
    ctx: ?*anyopaque,
    on_message: MessageHandler,
) !void {
    defer stream.close(io);

    var line_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &line_buf);
    const reader = &stream_reader.interface;
    while (true) {
        const msg = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return error.LineTooLong,
            else => return err,
        } orelse break;

        on_message(allocator, ctx, msg) catch |e| {
            log.err("Error deserializing incoming message: {any}", .{e});
        };
    }

    log.info("connection closed\n", .{});
}
