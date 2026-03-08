const std = @import("std");
const main_compute = @import("main_compute");

const SOCKET_PATH: []const u8 = "/tmp/main_compute.sock";

const Streamer = struct {
    fd: i32,
    addr: std.net.Address,

    pub fn init(path: []const u8) !Streamer {
        const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
        const addr = try std.net.Address.initUnix(path);

        try std.posix.bind(fd, &addr.any, addr.getOsSockLen());
        try std.posix.listen(fd, 5);

        return .{
            .fd = fd,
            .addr = addr,
        };
    }

    pub fn deinit(self: *Streamer) void {
        std.posix.close(self.fd);
    }

    pub fn listen(
        self: Streamer,
        line_buf: []u8,
    ) !usize {
        const conn_fd = try std.posix.accept(self.fd, null, null, 0);
        const stream = std.net.Stream{ .handle = conn_fd };
        defer stream.close();

        // Read until EOF or buffer is full.
        var read_len: usize = 0;
        while (true) {
            if (read_len >= line_buf.len) break;
            const n = try stream.read(line_buf[read_len..]);
            if (n == 0) break;
            read_len += n;
        }

        return read_len;
    }
};

pub fn preStart() !Streamer {
    if (std.fs.accessAbsolute(SOCKET_PATH, .{})) |_| {
        try std.fs.deleteFileAbsolute(SOCKET_PATH);
    } else |_| {}

    return try Streamer.init(SOCKET_PATH);
}

pub fn main() !void {
    var streamer = try preStart();
    defer streamer.deinit();

    var buf: [4096]u8 = undefined;
    const n = try streamer.listen(&buf);

    std.debug.print("{s}\n", .{buf[0..n]});
}
