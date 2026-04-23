const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zon2tct = @import("zon2tct.zig");
const Compilation = zon2tct.Compilation;
const Diagnostics = zon2tct.Diagnostics;
const Driver = zon2tct.Driver;

var stderr_buf: [1024]u8 align(std.heap.page_size_min) = undefined;

fn fatalError(diagnostics: *Diagnostics, text: []const u8) noreturn {
    diagnostics.add(.{ .kind = .@"fatal error", .text = text, .location = null }) catch |err| switch (err) {
        error.FatalError => {
            const w = diagnostics.output.to_writer.writer;

            const warnings = diagnostics.warnings;
            const errors = diagnostics.errors;
            const w_s: []const u8 = if (warnings == 1) "" else "s";
            const e_s: []const u8 = if (errors == 1) "" else "s";
            if (errors != 0 and warnings != 0)
                w.print("{d} warning{s} and {d} error{s} generated.\n", .{ warnings, w_s, errors, e_s }) catch {}
            else if (warnings != 0)
                w.print("{d} warnings{s} generated.\n", .{ warnings, w_s }) catch {}
            else if (errors != 0)
                w.print("{d} error{s} generated.\n", .{ errors, e_s }) catch {};

            w.flush() catch {};

            std.process.exit(1);
        },
        error.OutOfMemory => unreachable,
    };
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

    const args = init.minimal.args.toSlice(arena) catch |err| fatalError(
        &diagnostics,
        Driver.errorDescription(err),
    );

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
        else => fatalError(&diagnostics, Driver.errorDescription(err)),
    };
}
