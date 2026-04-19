//! This is here because zig does not ship with channel in std.
//! If this grows big enough we would move it to its own folder.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// This is NOT a lockfree implementation (which would use @cmpxchgStrong)
/// We don't really need high throughput implementation here
/// (though we might want to do one in the future just for the fun of it)
pub fn Mpsc(comptime T: type) type {
    return struct {
        const Self = @This();

        const State = struct {
            allocator: Allocator,
            io: std.Io,
            mutex: std.Io.Mutex = .init,
            not_empty: std.Io.Condition = .init,
            not_full: std.Io.Condition = .init,
            buffer: []T,
            capacity: usize,
            head: usize = 0,
            tail: usize = 0,
            len: usize = 0,
            closed: bool = false,
        };

        state: *State,

        pub const Rx = struct {
            state: *State,

            pub fn recvWithTimeout(self: *const Rx, wait_until: std.Io.Clock.Timestamp) !T {
                const state = self.state;
                while (true) {
                    return self.tryRecv() catch |err| switch (err) {
                        error.WouldBlock => {
                            const now = std.Io.Clock.Timestamp.now(state.io, wait_until.clock);
                            if (std.Io.Clock.Timestamp.compare(now, .gt, wait_until)) {
                                return error.Timeout;
                            }

                            const time_left = now.durationTo(wait_until);
                            if (time_left.raw.nanoseconds == 0) return error.Timeout;

                            state.io.sleep(
                                .fromNanoseconds(@min(
                                    time_left.raw.nanoseconds,
                                    @as(i96, 1 * std.time.ns_per_ms),
                                )),
                                .awake,
                            ) catch unreachable;
                            continue;
                        },
                        else => return err,
                    };
                }
            }

            pub fn tryRecv(self: *const Rx) !T {
                const state = self.state;
                state.mutex.lockUncancelable(state.io);
                defer state.mutex.unlock(state.io);

                if (state.len == 0) {
                    if (state.closed) return error.Closed;
                    return error.WouldBlock;
                }

                const item = state.buffer[state.head];
                state.head = (state.head + 1) % state.capacity;
                state.len -= 1;
                state.not_full.signal(state.io);
                return item;
            }

            pub fn recv(self: *const Rx) !T {
                const state = self.state;
                state.mutex.lockUncancelable(state.io);
                defer state.mutex.unlock(state.io);

                while (state.len == 0) {
                    if (state.closed) return error.Closed;
                    state.not_empty.waitUncancelable(state.io, &state.mutex);
                }

                const item = state.buffer[state.head];
                state.head = (state.head + 1) % state.capacity;
                state.len -= 1;
                state.not_full.signal(state.io);
                return item;
            }
        };

        pub const Tx = struct {
            state: *State,

            pub fn trySend(self: *const Tx, item: T) !void {
                const state = self.state;
                state.mutex.lockUncancelable(state.io);
                defer state.mutex.unlock(state.io);

                if (state.closed) return error.Closed;
                if (state.len == state.capacity) return error.WouldBlock;

                state.buffer[state.tail] = item;
                state.tail = (state.tail + 1) % state.capacity;
                state.len += 1;
                state.not_empty.signal(state.io);
            }

            pub fn send(self: *const Tx, item: T) !void {
                const state = self.state;
                state.mutex.lockUncancelable(state.io);
                defer state.mutex.unlock(state.io);

                while (state.len == state.capacity) {
                    if (state.closed) return error.Closed;
                    state.not_full.waitUncancelable(state.io, &state.mutex);
                }

                state.buffer[state.tail] = item;
                state.tail = (state.tail + 1) % state.capacity;
                state.len += 1;
                state.not_empty.signal(state.io);
            }

            pub fn close(self: *const Tx) void {
                const state = self.state;
                state.mutex.lockUncancelable(state.io);
                defer state.mutex.unlock(state.io);

                state.closed = true;
                state.not_empty.broadcast(state.io);
                state.not_full.broadcast(state.io);
            }
        };

        pub fn init(allocator: Allocator, capacity: usize, io: std.Io) !Self {
            const state = try allocator.create(State);
            errdefer allocator.destroy(state);

            const buffer = try allocator.alloc(T, capacity);
            errdefer allocator.free(buffer);

            state.* = .{
                .allocator = allocator,
                .io = io,
                .buffer = buffer,
                .capacity = capacity,
            };

            return .{ .state = state };
        }

        pub fn split(self: *Self) struct { tx: Tx, rx: Rx } {
            return .{
                .tx = .{ .state = self.state },
                .rx = .{ .state = self.state },
            };
        }

        pub fn deinit(self: *Self) void {
            const state = self.state;
            state.allocator.free(state.buffer);
            state.allocator.destroy(state);
        }
    };
}

fn instantAfter(io: std.Io, timeout_ns: u64) std.Io.Clock.Timestamp {
    return std.Io.Clock.Timestamp.fromNow(io, .{
        .raw = .fromNanoseconds(@intCast(timeout_ns)),
        .clock = .awake,
    });
}

test "spsc sends across threads" {
    const testing = std.testing;
    var channel = try Mpsc(u32).init(testing.allocator, 8, testing.io);
    defer channel.deinit();

    const parts = channel.split();
    const N: u32 = 1000;

    const Producer = struct {
        fn run(tx: Mpsc(u32).Tx, count: u32) void {
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                tx.send(i) catch @panic("send failed");
            }
            tx.close();
        }
    };

    const thread = try std.Thread.spawn(.{}, Producer.run, .{ parts.tx, N });
    defer thread.join();

    var sum: u64 = 0;
    var i: u32 = 0;
    while (i < N) : (i += 1) {
        const value = try parts.rx.recv();
        sum += value;
    }

    try testing.expectError(error.Closed, parts.rx.recv());
    try testing.expectEqual(@as(u64, (N - 1) * N / 2), sum);
}

test "spsc blocks until send from another thread" {
    const testing = std.testing;
    var channel = try Mpsc(u8).init(testing.allocator, 1, testing.io);
    defer channel.deinit();

    const parts = channel.split();

    const Producer = struct {
        fn run(tx: Mpsc(u8).Tx) void {
            tx.state.io.sleep(.fromNanoseconds(10 * std.time.ns_per_ms), .awake) catch unreachable;
            tx.send(42) catch @panic("send failed");
            tx.close();
        }
    };

    const thread = try std.Thread.spawn(.{}, Producer.run, .{parts.tx});
    defer thread.join();

    const value = try parts.rx.recv();
    try testing.expectEqual(@as(u8, 42), value);
    try testing.expectError(error.Closed, parts.rx.recv());
}

test "trySend returns WouldBlock when full" {
    const testing = std.testing;
    var channel = try Mpsc(u8).init(testing.allocator, 1, testing.io);
    defer channel.deinit();

    const parts = channel.split();
    try parts.tx.trySend(7);
    try testing.expectError(error.WouldBlock, parts.tx.trySend(8));
    try testing.expectEqual(@as(u8, 7), try parts.rx.recv());
}

test "recvWithTimeout returns buffered item immediately" {
    const testing = std.testing;
    var channel = try Mpsc(u8).init(testing.allocator, 1, testing.io);
    defer channel.deinit();

    const parts = channel.split();
    try parts.tx.trySend(42);

    try testing.expectEqual(
        @as(u8, 42),
        try parts.rx.recvWithTimeout(std.Io.Clock.Timestamp.now(testing.io, .awake)),
    );
}

test "recvWithTimeout drains buffered item after close" {
    const testing = std.testing;
    var channel = try Mpsc(u8).init(testing.allocator, 1, testing.io);
    defer channel.deinit();

    const parts = channel.split();
    try parts.tx.trySend(9);
    parts.tx.close();

    try testing.expectEqual(
        @as(u8, 9),
        try parts.rx.recvWithTimeout(std.Io.Clock.Timestamp.now(testing.io, .awake)),
    );
    try testing.expectError(
        error.Closed,
        parts.rx.recvWithTimeout(instantAfter(testing.io, 10 * std.time.ns_per_ms)),
    );
}

test "recvWithTimeout returns closed when channel closes while empty" {
    const testing = std.testing;
    var channel = try Mpsc(u8).init(testing.allocator, 1, testing.io);
    defer channel.deinit();

    const parts = channel.split();

    const Closer = struct {
        fn run(tx: Mpsc(u8).Tx) void {
            tx.state.io.sleep(.fromNanoseconds(10 * std.time.ns_per_ms), .awake) catch unreachable;
            tx.close();
        }
    };

    const thread = try std.Thread.spawn(.{}, Closer.run, .{parts.tx});
    defer thread.join();

    try testing.expectError(
        error.Closed,
        parts.rx.recvWithTimeout(instantAfter(testing.io, 100 * std.time.ns_per_ms)),
    );
}

test "recvWithTimeout times out when no item arrives" {
    const testing = std.testing;
    var channel = try Mpsc(u8).init(testing.allocator, 1, testing.io);
    defer channel.deinit();

    const parts = channel.split();

    try testing.expectError(
        error.Timeout,
        parts.rx.recvWithTimeout(instantAfter(testing.io, 20 * std.time.ns_per_ms)),
    );
}
