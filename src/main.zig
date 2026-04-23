const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zon2tct = @import("zon2tct.zig");
const Compilation = zon2tct.Compilation;
const Diagnostics = zon2tct.Diagnostics;
const Driver = zon2tct.Driver;

var stdout_buf: [4096]u8 align(std.heap.page_size_min) = undefined;
var artifact_buf: [4096]u8 align(std.heap.page_size_min) = undefined;

fn fatalErrorFilename(name: []const u8, err: anyerror) noreturn {
    std.process.fatal("{s}: {s}", .{ name, Driver.errorDescription(err) });
}

fn fatalError(err: anyerror) noreturn {
    std.process.fatal("{s}", .{Driver.errorDescription(err)});
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

    var stderr_buf: [1024]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &stderr_buf);
    var diagnostics: Diagnostics = .{
        .output = .{
            .to_writer = .{
                .mode = std.Io.Terminal.Mode.detect(io, stderr.file, false, false) catch .no_color,
                .writer = &stderr.interface,
            },
        },
    };

    var comp: Compilation = .{
        .gpa = init.gpa,
        .arena = arena,
        .io = io,
        .cwd = Io.Dir.cwd(),
    };

    var driver: Driver = .{
        .comp = &comp,
        .diagnostics = &diagnostics,
    };

    driver.main(args) catch |err| switch (err) {
        error.FatalError => {
            driver.printDiagnosticsStats();
            std.process.exit(1);
        },
        //error.Canceled => unreachable,
        else => fatalError(err),
    };
}
