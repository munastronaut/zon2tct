const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zon2tct = @import("zon2tct.zig");
const Compilation = zon2tct.Compilation;
const Driver = zon2tct.Driver;

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
    std.process.fatal("{s}: {s}", .{ name, errorDescription(err) });
}

fn fatalError(err: anyerror) noreturn {
    std.process.fatal("{s}", .{errorDescription(err)});
}

pub fn main(init: std.process.Init) void {
    //const env = init.environ_map;
    const io = init.io;
    const arena = init.arena.allocator();

    //var args = init.minimal.args.iterateAllocator(allocator) catch |err| fatalError(err);
    //_ = args.next();
    //const input = args.next() orelse std.process.fatal("no input file", .{});
    //const output = args.next() orelse std.mem.concat(
    //    allocator,
    //    u8,
    //    &.{ Io.Dir.path.stem(input), ".js" },
    //) catch |err| fatalError(err);

    //const cwd = Io.Dir.cwd();
    //const src = cwd.readFileAllocOptions(
    //    io,
    //    input,
    //    allocator,
    //    .limited(std.math.maxInt(u32)),
    //    .of(u8),
    //    0,
    //) catch |err| fatalErrorFilename(input, err);

    const args = init.minimal.args.toSlice(arena) catch |err| fatalError(err);

    var comp: Compilation = .{
        .gpa = init.gpa,
        .arena = arena,
        .io = io,
        .cwd = Io.Dir.cwd(),
    };

    var d: Driver = .{
        .comp = &comp,
    };

    d.main(args) catch |err| fatalError(err);
}
