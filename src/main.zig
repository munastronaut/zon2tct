const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const path = std.fs.path;

const Lexer = @import("Lexer.zig");

var stdout_buf: [4096]u8 align(std.heap.page_size_min) = undefined;
var artifact_buf: [4096]u8 align(std.heap.page_size_min) = undefined;

fn errorDescription(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "no such file or directory",
        error.NotDir => "not a directory",
        error.IsDir => "is a directory",
        else => @errorName(err),
    };
}

fn fatalError(name: []const u8, err: anyerror) noreturn {
    const desc = errorDescription(err);
    std.process.fatal("{s}: {s}", .{ name, desc });
}

fn openDirIfAbs(io: Io, name: []const u8) ?Io.Dir {
    if (path.isAbsolute(name)) {
        const dirname = path.dirname(name).?;
        return Io.Dir.openDirAbsolute(io, dirname, .{}) catch |err| fatalError(dirname, err);
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    const env = init.environ_map;
    const io = init.io;
    const allocator = init.arena.allocator();

    var args = init.minimal.args.iterate();
    _ = args.next();
    const input = args.next() orelse std.process.fatal("no input file", .{});
    const output = args.next() orelse try std.mem.concat(allocator, u8, &.{ path.stem(input), ".js" });

    const src_dir: Io.Dir = openDirIfAbs(io, input) orelse .cwd();

    const src = src_dir.readFileAllocOptions(io, input, allocator, .limited(std.math.maxInt(u32)), .of(u8), 0) catch |err| fatalError(input, err);

    var stdout_w = Io.File.stdout().writer(io, &stdout_buf);

    const clicolor_force = if (env.get("CLICOLOR_FORCE")) |v|
        !std.mem.eql(u8, v, "0")
    else
        false;

    const no_color = env.contains("NO_COLOR");

    const term_mode = try Io.Terminal.Mode.detect(
        io,
        stdout_w.file,
        no_color,
        clicolor_force,
    );

    const t: Io.Terminal = .{
        .mode = term_mode,
        .writer = &stdout_w.interface,
    };

    var lexer = Lexer.init(src);
    var tok_count: usize = 1;
    while (true) : (tok_count += 1) {
        const tok = lexer.next();
        try lexer.output(t, tok, tok_count);
        if (tok.id == .eof) break;
    }
    try t.writer.flush();

    const artifact_dir: Io.Dir = openDirIfAbs(io, output) orelse .cwd();

    var artifact_file = try artifact_dir.createFile(io, output, .{});
    var artifact_w = artifact_file.writer(io, &artifact_buf);
    const artifact = &artifact_w.interface;

    try artifact.writeAll("const noop = () => {};\nnoop();");
    try artifact.flush();
}
