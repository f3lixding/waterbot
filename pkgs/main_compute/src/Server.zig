const std = @import("std");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const PORT: u16 = 8888;

pub fn run(allocator: Allocator, socket_path: []const u8) !void {
    _ = socket_path;

    var server = try httpz.Server(void).init(allocator, .{
        .address = .all(PORT),
    }, {});
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});
    router.get("/home", serveHome, .{});

    std.debug.print("listening http://0.0.0.0:{d}/\n", .{PORT});
    try server.listen();
}

fn serveHome(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <meta charset="utf-8" />
        \\    <title>Waterbot</title>
        \\  </head>
        \\  <body>
        \\    <h1>Waterbot</h1>
        \\    <p>Home page placeholder.</p>
        \\  </body>
        \\</html>
    ;
}

pub fn main() void {
    const SOCKET_PATH = "/tmp/main_compute.sock";
    const allocator = std.heap.page_allocator;
    run(allocator, SOCKET_PATH) catch unreachable;
}
