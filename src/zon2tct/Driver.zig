const std = @import("std");
const mem = std.mem;

const Compilation = @import("Compilation.zig");

const Driver = @This();

comp: *Compilation,
output_name: ?[]const u8 = null,

pub const Error = std.mem.Allocator.Error;

pub fn main(d: *Driver, args: []const []const u8) !void {
    var stdout_buf: [512]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(d.comp.io, &stdout_buf);
    return d.parseArgs(&stdout.interface, args);
}

pub const usage =
    \\Usage: {s} [options] file..
    \\
    \\Options:
    \\  --help           Display this messsage
    \\  --name <name>    Write the output to <name>
    \\
;

pub fn parseArgs(d: *Driver, stdout: *std.Io.Writer, args: []const []const u8) std.Io.Writer.Error!void {
    const gpa = d.comp.gpa;
    _ = gpa;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len > 1 and arg[0] == '-') {
            if (mem.eql(u8, arg, "--help")) {
                try stdout.print(usage, .{args[0]});
                try stdout.flush();
                return;
            } else if (mem.eql(u8, arg, "--name")) {
                i += 1;
                if (i >= args.len) {}
                d.output_name = args[i];
            }
        }
    }
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
