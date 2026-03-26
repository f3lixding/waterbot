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
            mutex: std.Thread.Mutex = .{},
            not_empty: std.Thread.Condition = .{},
            not_full: std.Thread.Condition = .{},
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

            pub fn recv(self: *const Rx) !T {
                const state = self.state;
                state.mutex.lock();
                defer state.mutex.unlock();

                while (state.len == 0) {
                    if (state.closed) return error.Closed;
                    state.not_empty.wait(&state.mutex);
                }

                const item = state.buffer[state.head];
                state.head = (state.head + 1) % state.capacity;
                state.len -= 1;
                state.not_full.signal();
                return item;
            }
        };

        pub const Tx = struct {
            state: *State,

            pub fn send(self: *const Tx, item: T) !void {
                const state = self.state;
                state.mutex.lock();
                defer state.mutex.unlock();

                while (state.len == state.capacity) {
                    if (state.closed) return error.Closed;
                    state.not_full.wait(&state.mutex);
                }

                state.buffer[state.tail] = item;
                state.tail = (state.tail + 1) % state.capacity;
                state.len += 1;
                state.not_empty.signal();
            }

            pub fn close(self: *const Tx) void {
                const state = self.state;
                state.mutex.lock();
                defer state.mutex.unlock();

                state.closed = true;
                state.not_empty.broadcast();
                state.not_full.broadcast();
            }
        };

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            const state = try allocator.create(State);
            errdefer allocator.destroy(state);

            const buffer = try allocator.alloc(T, capacity);
            errdefer allocator.free(buffer);

            state.* = .{
                .allocator = allocator,
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

test "spsc sends across threads" {
    const testing = std.testing;
    var channel = try Mpsc(u32).init(testing.allocator, 8);
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
    var channel = try Mpsc(u8).init(testing.allocator, 1);
    defer channel.deinit();

    const parts = channel.split();

    const Producer = struct {
        fn run(tx: Mpsc(u8).Tx) void {
            std.Thread.sleep(10 * std.time.ns_per_ms);
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
