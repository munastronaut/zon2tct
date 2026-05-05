const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zon2tct = @import("zon2tct");

pub const std_options: std.Options = .{
    .logFn = log,
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buf: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buf).terminal();
    defer std.debug.unlockStderr();
    return logInner(level, scope, format, args, stderr) catch {};
}

pub fn logInner(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
    t: Io.Terminal,
) Io.Writer.Error!void {
    t.setColor(switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    }) catch {};
    t.setColor(.bold) catch {};
    try t.writer.writeAll(level.asText());
    if (scope != .default) try t.writer.print(" ({t})", .{scope});
    try t.writer.writeAll(": ");
    t.setColor(.reset) catch {};
    t.setColor(.bold) catch {};
    try t.writer.print(format ++ "\n", args);
}

pub fn main(init: std.process.Init) void {
    const env = init.environ_map;
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    _ = env;
    _ = io;
    _ = gpa;
    _ = arena;
}
