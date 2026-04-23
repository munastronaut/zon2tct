const std = @import("std");
const mem = std.mem;

const Compilation = @import("Compilation.zig");
const Diagnostics = @import("Diagnostics.zig");

const Driver = @This();

comp: *Compilation,
diagnostics: *Diagnostics,
output_name: ?[]const u8 = null,

pub const Error = std.mem.Allocator.Error;

pub fn errorDescription(er: anyerror) []const u8 {
    return switch (er) {
        error.WriteFailed => "failed to write to file",
        error.OutOfMemory => "ran out of memory",
        error.FileNotFound => "no such file or directory",
        error.NotDir => "not a directory",
        error.IsDir => "is a directory",
        else => @errorName(er),
    };
}

pub fn fatal(d: *Driver, comptime fmt: []const u8, args: anytype) error{ FatalError, OutOfMemory } {
    try d.log(fmt, args, .@"fatal error");
    unreachable;
}

pub fn err(d: *Driver, comptime fmt: []const u8, args: anytype) error{ FatalError, OutOfMemory }!void {
    try d.log(fmt, args, .@"error");
}

pub fn warn(d: *Driver, comptime fmt: []const u8, args: anytype) error{ FatalError, OutOfMemory }!void {
    try d.log(fmt, args, .warning);
}

fn log(d: *Driver, comptime fmt: []const u8, args: anytype, kind: Diagnostics.Message.Kind) error{ FatalError, OutOfMemory }!void {
    var sf = std.heap.stackFallback(1024, d.comp.gpa);
    var allocating: std.Io.Writer.Allocating = .init(sf.get());
    defer allocating.deinit();

    Diagnostics.formatArgs(&allocating.writer, fmt, args) catch return error.OutOfMemory;
    try d.diagnostics.add(.{ .kind = kind, .text = allocating.written(), .location = null });
}

pub fn printDiagnosticsStats(d: *Driver) void {
    if (!d.diagnostics.details) return;
    const warnings = d.diagnostics.warnings;
    const errors = d.diagnostics.errors;

    var buf: [64]u8 = undefined;
    const stderr = d.comp.io.lockStderr(&buf, .no_color) catch unreachable;
    defer d.comp.io.unlockStderr();

    const w = &stderr.file_writer.interface;

    const w_s: []const u8 = if (warnings == 1) "" else "s";
    const e_s: []const u8 = if (errors == 1) "" else "s";
    if (errors != 0 and warnings != 0)
        w.print("{d} warning{s} and {d} error{s} generated.\n", .{ warnings, w_s, errors, e_s }) catch return
    else if (warnings != 0)
        w.print("{d} warnings{s} generated.\n", .{ warnings, w_s }) catch return
    else if (errors != 0)
        w.print("{d} error{s} generated.\n", .{ errors, e_s }) catch return;
}

pub fn main(d: *Driver, args: []const []const u8) !void {
    var stdout_buf: [512]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(d.comp.io, &stdout_buf);
    if (d.parseArgs(&stdout.interface, args) catch |er| switch (er) {
        error.WriteFailed => return d.fatal("failed to write to stdout: {s}", .{errorDescription(er)}),
        error.OutOfMemory => return error.OutOfMemory,
        error.FatalError => return error.FatalError,
    }) return;

    d.printDiagnosticsStats();
}

pub const usage =
    \\Usage: {s} [options] file..
    \\
    \\Options:
    \\  --help           Display this messsage
    \\  --name <name>    Write the output to <name>
    \\
;

pub fn parseArgs(d: *Driver, stdout: *std.Io.Writer, args: []const []const u8) !bool {
    const gpa = d.comp.gpa;
    _ = gpa;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len > 1 and arg[0] == '-') {
            if (mem.eql(u8, arg, "--help")) {
                try stdout.print(usage, .{args[0]});
                try stdout.flush();
                return true;
            } else if (mem.eql(u8, arg, "--name")) {
                i += 1;
                if (i >= args.len) {
                    try d.err("expected argument after --name", .{});
                    continue;
                }
                d.output_name = args[i];
            } else {
                try d.warn("unknown argument '{s}'", .{arg});
            }
        } else {
            // TODO handle source files here
        }
    }
    return false;
}

test "parse name" {
    const args: []const []const u8 = &[_][]const u8{ "zon2tct", "input.zon", "--name", "output.js" };

    var comp: Compilation = .{
        .gpa = std.testing.allocator,
        .arena = std.testing.allocator,
        .io = std.testing.io,
        .cwd = std.Io.Dir.cwd(),
    };

    var d: Driver = .{
        .comp = &comp,
    };

    try d.main(args);

    try std.testing.expectEqualStrings("output.js", d.output_name.?);
}
