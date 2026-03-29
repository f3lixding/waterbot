const std = @import("std");
const httpz = @import("httpz");
const protocol = @import("protocol.zig");

const Allocator = std.mem.Allocator;
const PORT: u16 = 8888;
const websocket = httpz.websocket;
const CvOrderTx = @import("main.zig").CvOrderTx;

const logging = std.log.scoped(.server);

const Handler = struct {
    socket_path: []const u8,
    order_tx: ?*CvOrderTx,

    pub const WebsocketHandler = Client;
};

const Client = struct {
    conn: *websocket.Conn,
    backend_stream: std.net.Stream,

    const Context = struct {
        socket_path: []const u8,
    };

    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        const backend_stream = try connectBackend(ctx.socket_path);
        return .{
            .conn = conn,
            .backend_stream = backend_stream,
        };
    }

    pub fn afterInit(self: *Client) !void {
        try self.conn.write("connected");
    }

    // This is a method expected by httpz
    pub fn clientMessage(self: *Client, data: []const u8) !void {
        _ = protocol.Command.fromBytes(std.heap.page_allocator, data) catch {
            try self.conn.write("expected a valid Command JSON payload");
            return;
        };

        try self.backend_stream.writeAll(data);
        try self.backend_stream.writeAll("\n");
        try self.conn.write(data);
    }

    pub fn close(self: *Client) void {
        self.backend_stream.close();
    }
};

pub fn run(allocator: Allocator, socket_path: []const u8, order_tx: ?*CvOrderTx) !void {
    var handler = Handler{
        .socket_path = socket_path,
        .order_tx = order_tx,
    };

    var server = try httpz.Server(*Handler).init(allocator, .{
        .address = .all(PORT),
    }, &handler);
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});
    router.get("/home", serveHome, .{});
    router.get("/ws", serveWebsocket, .{});
    router.get("/cv", serveCvOrder, .{});
    router.get("/cv/stop", serveCvStopOrder, .{});

    logging.info("Serving at port: {d}", .{PORT});

    try server.listen();
}

fn serveHome(_: *Handler, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.content_type = .HTML;
    res.body =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <meta charset="utf-8" />
        \\    <title>Waterbot</title>
        \\    <style>
        \\      :root {
        \\        font-family: sans-serif;
        \\      }
        \\      body {
        \\        margin: 0;
        \\        min-height: 100vh;
        \\        display: grid;
        \\        place-items: center;
        \\        background: linear-gradient(135deg, #d8f0ff, #f7fbff);
        \\      }
        \\      main {
        \\        padding: 2rem;
        \\        border: 1px solid #9bc7e5;
        \\        border-radius: 1rem;
        \\        background: rgba(255, 255, 255, 0.9);
        \\        box-shadow: 0 1rem 2rem rgba(49, 94, 130, 0.15);
        \\      }
        \\      .controls {
        \\        display: flex;
        \\        gap: 1rem;
        \\        margin-top: 1rem;
        \\        justify-content: center;
        \\      }
        \\      button {
        \\        min-width: 8rem;
        \\        padding: 0.9rem 1.2rem;
        \\        border: 0;
        \\        border-radius: 999px;
        \\        font-size: 1rem;
        \\        font-weight: 700;
        \\        background: #0f6cbd;
        \\        color: white;
        \\        cursor: pointer;
        \\      }
        \\      button:disabled {
        \\        background: #8ca8bf;
        \\        cursor: wait;
        \\      }
        \\      #status {
        \\        margin-top: 1rem;
        \\      }
        \\    </style>
        \\  </head>
        \\  <body>
        \\    <main>
        \\      <h1>Waterbot</h1>
        \\      <p>Use one websocket connection and send commands with the buttons below.</p>
        \\      <div class="controls">
        \\        <button id="left" disabled>left</button>
        \\        <button id="stop" disabled>stop</button>
        \\        <button id="right" disabled>right</button>
        \\      </div>
        \\      <div class="controls">
        \\        <button id="cv-order">run cv order</button>
        \\        <button id="cv-stop">stop cv order</button>
        \\      </div>
        \\      <p id="status">Connecting...</p>
        \\    </main>
        \\    <script>
        \\      const status = document.getElementById("status");
        \\      const left = document.getElementById("left");
        \\      const right = document.getElementById("right");
        \\      const stop = document.getElementById("stop");
        \\      const cvOrder = document.getElementById("cv-order");
        \\      const cvStop = document.getElementById("cv-stop");
        \\      const buttons = [left, stop, right];
        \\
        \\      const setConnected = (connected) => {
        \\        for (const button of buttons) button.disabled = !connected;
        \\      };
        \\
        \\      const buildCommand = (direction) => JSON.stringify({
        \\        direction: direction === "stop"
        \\          ? { stop: {} }
        \\          : { [direction]: { speed: 10 } },
        \\      });
        \\
        \\      const scheme = window.location.protocol === "https:" ? "wss" : "ws";
        \\      const ws = new WebSocket(`${scheme}://${window.location.host}/ws`);
        \\
        \\      ws.addEventListener("open", () => {
        \\        setConnected(true);
        \\        status.textContent = "Connected";
        \\      });
        \\
        \\      ws.addEventListener("message", (event) => {
        \\        status.textContent = `Last message: ${event.data}`;
        \\      });
        \\
        \\      ws.addEventListener("close", () => {
        \\        setConnected(false);
        \\        status.textContent = "Disconnected";
        \\      });
        \\
        \\      ws.addEventListener("error", () => {
        \\        setConnected(false);
        \\        status.textContent = "Websocket error";
        \\      });
        \\
        \\      cvOrder.addEventListener("click", async () => {
        \\        cvOrder.disabled = true;
        \\        status.textContent = "Queueing cv order...";
        \\
        \\        try {
        \\          const response = await fetch("/cv");
        \\          const text = await response.text();
        \\          status.textContent = text;
        \\        } catch (_) {
        \\          status.textContent = "Failed to queue cv order";
        \\        } finally {
        \\          cvOrder.disabled = false;
        \\        }
        \\      });
        \\
        \\      cvStop.addEventListener("click", async () => {
        \\        cvStop.disabled = true;
        \\        status.textContent = "Queueing cv stop order...";
        \\
        \\        try {
        \\          const response = await fetch("/cv/stop");
        \\          const text = await response.text();
        \\          status.textContent = text;
        \\        } catch (_) {
        \\          status.textContent = "Failed to queue cv stop order";
        \\        } finally {
        \\          cvStop.disabled = false;
        \\        }
        \\      });
        \\
        \\      left.addEventListener("click", () => ws.send(buildCommand("left")));
        \\      stop.addEventListener("click", () => ws.send(buildCommand("stop")));
        \\      right.addEventListener("click", () => ws.send(buildCommand("right")));
        \\    </script>
        \\  </body>
        \\</html>
    ;
}

fn serveWebsocket(handler: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const ctx = Client.Context{ .socket_path = handler.socket_path };

    if (try httpz.upgradeWebsocket(Client, req, res, &ctx) == false) {
        res.status = 400;
        res.body = "invalid websocket";
    }
}

fn serveCvOrder(handler: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    if (handler.order_tx) |tx| {
        tx.trySend(.UntilCompliant) catch |err| {
            switch (err) {
                error.WouldBlock => {
                    res.status = 429;
                    res.content_type = .TEXT;
                    res.body = "cv order queue is full";
                    return;
                },
                error.Closed => {
                    res.status = 503;
                    res.content_type = .TEXT;
                    res.body = "cv pipeline is closed";
                    return;
                },
                else => return err,
            }
        };
        res.status = 202;
        res.content_type = .TEXT;
        res.body = "queued cv order";
        return;
    }

    logging.info("Received pipeline request without order tx", .{});
    res.status = 503;
    res.content_type = .TEXT;
    res.body = "cv pipeline unavailable";
}

fn serveCvStopOrder(handler: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    if (handler.order_tx) |tx| {
        tx.trySend(.Stop) catch |err| {
            switch (err) {
                error.WouldBlock => {
                    res.status = 429;
                    res.content_type = .TEXT;
                    res.body = "cv order queue is full";
                    return;
                },
                error.Closed => {
                    res.status = 503;
                    res.content_type = .TEXT;
                    res.body = "cv pipeline is closed";
                    return;
                },
                else => return err,
            }
        };
        res.status = 202;
        res.content_type = .TEXT;
        res.body = "queued cv stop order";
        return;
    }

    logging.info("Received pipeline stop request without order tx", .{});
    res.status = 503;
    res.content_type = .TEXT;
    res.body = "cv pipeline unavailable";
}

fn connectBackend(socket_path: []const u8) !std.net.Stream {
    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    errdefer std.posix.close(fd);

    const addr = try std.net.Address.initUnix(socket_path);
    try std.posix.connect(fd, &addr.any, addr.getOsSockLen());

    return .{ .handle = fd };
}

pub fn main() void {
    const SOCKET_PATH = "/tmp/main_compute.sock";
    const allocator = std.heap.page_allocator;
    run(allocator, SOCKET_PATH, null) catch unreachable;
}
