const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zon2tct = @import("zon2tct.zig");
const Compilation = zon2tct.Compilation;
const Diagnostics = zon2tct.Diagnostics;
const Driver = zon2tct.Driver;

var stderr_buf: [1024]u8 align(std.heap.page_size_min) = undefined;

// Not moving this into `Driver` because this is for errors during initialization, not during the
// actual driver phase.
fn fatalInitError(d: *Driver, comptime fmt: []const u8, args: anytype) noreturn {
    switch (d.fatal(fmt, args)) {
        error.FatalError => {
            d.printDiagnosticsStats();
            std.process.exit(1);
        },
        error.OutOfMemory => unreachable,
    }
    unreachable;
}

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();

    var stderr = Io.File.stderr().writer(io, &stderr_buf);
    var diagnostics: Diagnostics = .{
        .output = .{
            .to_writer = .{
                .mode = Io.Terminal.Mode.detect(io, stderr.file, false, false) catch .no_color,
                .writer = &stderr.interface,
            },
        },
    };

    var comp: Compilation = .{
        .gpa = init.gpa,
        .arena = arena,
        .io = io,
        .cwd = .cwd(),
    };

    var driver: Driver = .{
        .comp = &comp,
        .diagnostics = &diagnostics,
    };

    const args = init.minimal.args.toSlice(arena) catch |err| fatalInitError(&driver, "{s}", .{Driver.errorDescription(err)});

    driver.main(args) catch |err| switch (err) {
        error.FatalError => {
            driver.printDiagnosticsStats();
            std.process.exit(1);
        },
        error.OutOfMemory => fatalInitError(&driver, "{s}", .{Driver.errorDescription(err)}),
    };
}
