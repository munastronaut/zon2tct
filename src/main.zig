const builtin = @import("builtin");
const native_os = builtin.os.tag;

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
const Color = zon2tct.Color;
const EnvVar = zon2tct.EnvVar;
const build_options = @import("build_options");

pub const std_options: std.Options = .{
    .logFn = log,
};

var stdout_buf: [4096]u8 align(std.heap.page_size_min) = undefined;

const usage =
    \\Usage: {s} [command] [options]
    \\
    \\Commands:
    \\  build         Create scenario code from source
    \\  init          Create a template file in the current directory
    \\  version       Print version number and exit
    \\  help          Print this help and exit
    \\
    \\Options:
    \\  -h, --help    Print command-specific usage
    \\
;

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

const use_debug_allocator = native_os != .wasi and switch (builtin.mode) {
    .Debug, .ReleaseSafe => false,
    .ReleaseFast, .ReleaseSmall => true,
};

const RootAllocator = if (use_debug_allocator) std.heap.DebugAllocator(.{
    .thread_safe = true,
}) else struct {
    pub const init: RootAllocator = .{};
    pub fn allocator(_: RootAllocator) Allocator {
        if (native_os == .wasi) return std.heap.wasm_allocator;
        return std.heap.smp_allocator;
    }
    pub fn deinit(_: RootAllocator) std.heap.Check {
        return .ok;
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    var root_allocator: RootAllocator = .init;
    defer _ = root_allocator.deinit();
    const root_gpa = root_allocator.allocator();
    var threaded: Io.Threaded = .init(root_gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    const io = threaded.io();
    const gpa = root_gpa;
    var arena_instance: std.heap.ArenaAllocator = .init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try init.args.toSlice(arena);

    if (args.len <= 1) fatal("expected command argument", .{});

    var environ_map = init.environ.createMap(arena) catch |err| {
        fatal("failed to parse environment: {t}", .{err});
    };

    return mainArgs(gpa, arena, io, args, &environ_map);
}

fn mainArgs(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    args: []const [:0]const u8,
    environ_map: *process.Environ.Map,
) !void {
    const cmd = args[1];

    if (mem.eql(u8, cmd, "build")) {
        return buildOutput(gpa, arena, io, args, environ_map);
    } else if (mem.eql(u8, cmd, "init")) {
        return cmdInit(arena, io, args);
    } else if (mem.eql(u8, cmd, "version")) {
        try Io.File.stdout().writeStreamingAll(io, build_options.version ++ "\n");
        return;
    } else if (mem.eql(u8, cmd, "help") or mem.eql(u8, cmd, "-h") or mem.eql(u8, cmd, "--help")) {
        return printUsage(io, usage, args[0]);
    } else {
        fatal("unrecognized command: '{s}'", .{cmd});
    }
}

fn printUsage(io: Io, comptime str: []const u8, exe_name: []const u8) !void {
    var w = Io.File.stdout().writer(io, &stdout_buf);
    try w.interface.print(str, .{exe_name});
    try w.interface.flush();
    return cleanExit(io);
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
        return it.next() orelse fatal("expected argument after '{s}'", .{it.args[it.i - 1]});
    }
};

const usage_build =
    \\Usage: {s} build [options] file
    \\
    \\Options:
    \\  -h, --help       Print this help and exit
    \\  --name [name]    Write the output to name
    \\
;

fn buildOutput(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    args: []const []const u8,
    environ_map: *process.Environ.Map,
) !void {
    var provided_name: ?[]const u8 = null;
    var src_file: ?[]const u8 = null;

    const color: zon2tct.Color = if (EnvVar.NO_COLOR.isSet(environ_map))
        .off
    else if (EnvVar.CLICOLOR_FORCE.isSet(environ_map))
        .on
    else
        .auto;

    var args_iter: ArgsIterator = .{ .args = args[2..] };
    while (args_iter.next()) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                return printUsage(io, usage_build, args[0]);
            } else if (mem.eql(u8, arg, "--name")) {
                const name = args_iter.nextOrFatal();
                provided_name = name;
                if (!mem.eql(u8, name, path.basename(name)))
                    fatal("invalid file name '{s}': cannot contain folder separators", .{name});
            } else {
                fatal("unrecognized parameter: '{s}'", .{arg});
            }
        } else switch (Compilation.classifyFileExt(arg)) {
            .plaintext => {
                if (src_file) |_| {
                    fatal("too many positional arguments, only one source file is supported", .{});
                } else src_file = arg;
            },
            .unknown => fatal("unrecognized file extension of parameter '{s}'", .{arg}),
        }
    }

    if (src_file == null) fatal("expected positional argument or --name [name]", .{});

    const comp = Compilation.create(gpa, arena, io, .{
        .color = color,
        .src_file = src_file.?,
        .provided_name = provided_name,
    }) catch |err| {
        fatal("failed to create compilation: {t}", .{err});
    };
    try comp.work();

    return cleanExit(io);
}

const usage_init =
    \\Usage: {s} init [options]
    \\
    \\Options:
    \\  -m, --minimal    Use minimal init template
    \\  -h, --help       Print this help and exit
    \\  --name [name]    Specify project name for template file
    \\
;

fn cmdInit(arena: Allocator, io: Io, args: []const []const u8) !void {
    var proj_name: ?[]const u8 = null;
    var template: enum { example, minimal } = .example;

    var args_iter: ArgsIterator = .{ .args = args[2..] };
    while (args_iter.next()) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-m") or mem.eql(u8, arg, "--minimal")) {
                template = .minimal;
            } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                return printUsage(io, usage_init, args[0]);
            } else if (mem.eql(u8, arg, "--name")) {
                const name = args_iter.nextOrFatal();
                proj_name = name;
                if (!mem.eql(u8, name, path.basename(name)))
                    fatal("invalid file name '{s}': cannot contain folder separators", .{name});
            } else {
                fatal("unrecognized parameter: '{s}'", .{arg});
            }
        } else {
            fatal("unexpected extra parameter: '{s}'", .{arg});
        }
    }

    const filename = if (proj_name) |name| try mem.concat(arena, u8, &.{ name, ".zon" }) else "scenario.zon";

    switch (template) {
        .example => {
            const tmplt = @embedFile("templates/template.zon");
            if (writeSimpleTemplateFile(io, filename, tmplt)) |_| {
                std.log.info("created {s}", .{filename});
            } else |err| switch (err) {
                error.PathAlreadyExists => std.log.info(
                    "preserving already existing file: '{s}'",
                    .{filename},
                ),
                else => std.log.err("unable to write '{s}': {t}\n", .{ filename, err }),
            }
            return cleanExit(io);
        },
        .minimal => {
            const tmplt = @embedFile("templates/template_minimal.zon");
            writeSimpleTemplateFile(io, filename, tmplt) catch |err| switch (err) {
                error.PathAlreadyExists => fatal("refusing to overwrite '{s}'", .{filename}),
                else => fatal("failed to create '{s}': {t}", .{ filename, err }),
            };
            std.log.info("created {s}", .{filename});
            return cleanExit(io);
        },
    }
}

fn writeSimpleTemplateFile(io: Io, filename: []const u8, str: []const u8) !void {
    const f = try Io.Dir.cwd().createFile(io, filename, .{ .exclusive = true });
    defer f.close(io);
    var buf: [4096]u8 = undefined;
    var fw = f.writer(io, &buf);
    try fw.interface.writeAll(str);
    try fw.interface.flush();
}
