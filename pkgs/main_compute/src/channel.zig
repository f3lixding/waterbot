//! This is here because zig does not ship with channel in std.
//! If this grows big enough we would move it to its own folder.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// This is NOT a lockfree implementation (which would use @cmpxchgStrong)
/// We don't really need high throughput implementation here
/// (though we might want to do one in the future just for the fun of it)
pub fn Spsc(comptime T: type) type {
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

            pub fn recv(self: *Rx) !T {
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

            pub fn send(self: *Tx, item: T) !void {
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

            pub fn close(self: *Tx) void {
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
