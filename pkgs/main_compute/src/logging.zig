//! For now we will use lock to deal with this being called from multiple
//! threads.
//! Later on we will use an actor pattern to spawn a dedicated thread and use
//! dispatch pattern.
//!
//! TODOs:
//!
//! - adopt a dispatch pattern
//! - auto rotate
//! - auto clean up

const std = @import("std");

const LOG_LOCATION: []const u8 = "/tmp/waterbot.log";
// 50 MB
const SIZE_UPPERBOUND: u64 = 52_428_000;

var log_mutex: std.Io.Mutex = .init;
var log_file: ?std.Io.File = null;
var log_io: ?std.Io = null;
var log_level_set: std.log.Level = .info;

pub fn init(cap_level: std.log.Level, io: std.Io) !void {
    log_level_set = cap_level;
    log_io = io;
    if (log_file != null) return;

    log_file = std.Io.Dir.openFileAbsolute(io, LOG_LOCATION, .{
        .mode = .read_write,
    }) catch |err| switch (err) {
        error.FileNotFound => try std.Io.Dir.createFileAbsolute(io, LOG_LOCATION, .{
            .read = true,
            .truncate = false,
        }),
        else => return err,
    };

    // we don't have auto rotate right now so we'll settle for lazy checking
    const stat = try log_file.?.stat(io);
    if (stat.size > SIZE_UPPERBOUND) {
        log_file.?.close(io);
        try std.Io.Dir.deleteFileAbsolute(io, LOG_LOCATION);
        log_file = try std.Io.Dir.createFileAbsolute(io, LOG_LOCATION, .{
            .read = true,
            .truncate = false,
        });
    } else {
        var file_writer = log_file.?.writerStreaming(io, &.{});
        try file_writer.seekTo(stat.size);
    }
}

pub fn deinit() void {
    const io = log_io orelse return;
    if (log_file) |file| {
        file.close(io);
        log_file = null;
    }
    log_io = null;
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) > @intFromEnum(log_level_set)) return;

    const io = log_io orelse return;
    log_mutex.lockUncancelable(io);
    defer log_mutex.unlock(io);

    const file = log_file orelse return;

    var buf: [1024]u8 = undefined;
    var file_writer = file.writerStreaming(io, &buf);
    const writer = &file_writer.interface;

    const now = std.time.epoch.EpochSeconds{
        .secs = @intCast(std.Io.Clock.real.now(io).toSeconds()),
    };
    const day_seconds = now.getDaySeconds();
    const year_day = now.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC] [{s}] [{s}] ", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
        @tagName(level),
        @tagName(scope),
    }) catch return;
    writer.print(format, args) catch return;
    writer.writeByte('\n') catch return;
    writer.flush() catch return;
}
