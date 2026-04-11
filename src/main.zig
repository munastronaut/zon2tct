const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const path = std.fs.path;
const fatal = std.process.fatal;

const Lexer = @import("Lexer.zig");

var stdout_buf: [4096]u8 align(std.heap.page_size_min) = undefined;
var artifact_buf: [4096]u8 align(std.heap.page_size_min) = undefined;

fn errorDescription(err: anyerror) []const u8 {
    return switch (err) {
        error.WriteFailed => "failed to write to file",
        error.OutOfMemory => "ran out of memory",
        error.FileNotFound => "no such file or directory",
        error.NotDir => "not a directory",
        error.IsDir => "is a directory",
        else => @errorName(err),
    };
}

fn fatalErrorFilename(name: []const u8, err: anyerror) noreturn {
    fatal("{s}: {s}", .{ name, errorDescription(err) });
}

fn fatalError(err: anyerror) noreturn {
    fatal("{s}", .{errorDescription(err)});
}

fn openDirIfAbs(io: Io, name: []const u8) ?Io.Dir {
    if (!path.isAbsolute(name)) return null;
    const dirname = path.dirname(name) orelse name;
    return Io.Dir.openDirAbsolute(io, dirname, .{}) catch |err| fatalErrorFilename(dirname, err);
}

pub fn main(init: std.process.Init) void {
    const env = init.environ_map;
    const io = init.io;
    const allocator = init.arena.allocator();

    var args = init.minimal.args.iterate();
    _ = args.next();
    const input = args.next() orelse fatal("no input file", .{});
    const output = args.next() orelse std.mem.concat(
        allocator,
        u8,
        &.{ path.stem(input), ".js" },
    ) catch |err| fatalError(err);

    const src_dir: Io.Dir = openDirIfAbs(io, input) orelse .cwd();
    const src = src_dir.readFileAllocOptions(
        io,
        input,
        allocator,
        .limited(std.math.maxInt(u32)),
        .of(u8),
        0,
    ) catch |err| fatalErrorFilename(input, err);

    var stdout_w = Io.File.stdout().writer(io, &stdout_buf);

    const clicolor_force = if (env.get("CLICOLOR_FORCE")) |v|
        !std.mem.eql(u8, v, "0")
    else
        false;

    const no_color = env.contains("NO_COLOR");

    const term_mode = Io.Terminal.Mode.detect(
        io,
        stdout_w.file,
        no_color,
        clicolor_force,
    ) catch .no_color;

    const t: Io.Terminal = .{
        .mode = term_mode,
        .writer = &stdout_w.interface,
    };

    var lexer = Lexer.init(src);
    var tok_count: usize = 1;
    while (true) : (tok_count += 1) {
        const tok = lexer.next();
        lexer.output(t, tok, tok_count) catch |err| fatalError(err);
        if (tok.id == .eof) break;
    }
    t.writer.flush() catch |err| fatalError(err);

    const artifact_dir: Io.Dir = openDirIfAbs(io, output) orelse .cwd();
    var artifact_file = artifact_dir.createFile(io, output, .{}) catch |err| fatalError(err);
    var artifact_w = artifact_file.writer(io, &artifact_buf);
    const artifact = &artifact_w.interface;

    artifact.writeAll("const noop = () => {};\nnoop();") catch |err| fatalError(err);
    artifact.flush() catch |err| fatalError(err);
}
