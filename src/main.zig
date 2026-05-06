const std = @import("std");

const Io = std.Io;
const path = Io.Dir.path;

const mem = std.mem;
const Allocator = mem.Allocator;

const process = std.process;
const fatal = process.fatal;
const exit = process.exit;
const cleanExit = process.cleanExit;

const Compilation = @import("Compilation.zig");

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
    t.setColor(.reset) catch {};
}

const usage =
    \\Usage: {s} [options] file..
    \\
    \\Options:
    \\  --help           Display this message
    \\  --name [name]    Write the output to [name]
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    return mainArgs(gpa, arena, io, args);
}

fn mainArgs(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    args: []const [:0]const u8,
) !void {
    var provided_name: ?[]const u8 = null;
    var src_file: ?[]const u8 = null;
    _ = gpa;
    _ = arena;

    var args_iter: ArgsIterator = .{
        .args = args[1..],
    };

    //args_loop: while (args_iter.next()) |arg| {
    while (args_iter.next()) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                var buf: [64]u8 = undefined;
                var wrt = Io.File.stdout().writer(io, &buf);
                try wrt.interface.print(usage, .{args[0]});
                try wrt.interface.flush();
                return cleanExit(io);
            } else if (mem.eql(u8, arg, "--name")) {
                provided_name = args_iter.nextOrFatal();
                if (!mem.eql(u8, provided_name.?, path.basename(provided_name.?)))
                    fatal("invalid file name '{s}': cannot contain folder separators", .{provided_name.?});
            } else {
                fatal("unrecognized parameter: '{s}'", .{arg});
            }
        } else switch (Compilation.classifyFileExt(arg)) {
            .plaintext => {
                if (src_file) |_| {
                    fatal("too many positional arguments, only one source file is supported", .{});
                } else src_file = arg;
                std.log.debug("src_file is {s}", .{src_file.?});
            },
            .unknown => fatal("unrecognized file extension of parameter '{s}'", .{arg}),
        }
    }

    if (src_file == null) fatal("expected a positional argument or --name [name]", .{});
}

const ArgsIterator = struct {
    args: []const []const u8,
    i: usize = 0,

    pub fn next(it: *@This()) ?[]const u8 {
        if (it.i >= it.args.len) return null;
        defer it.i += 1;
        return it.args[it.i];
    }

    pub fn nextOrFatal(it: *@This()) []const u8 {
        return it.next() orelse fatal("expected argument after {s}", .{it.args[it.i - 1]});
    }
};
