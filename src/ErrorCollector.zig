const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Location = @import("common.zig").Location;

const Severity = enum {
    @"error",
    warning,
    note,
};

const Diagnostics = struct {
    severity: Severity,
    line: usize,
    column: usize,
    message: []const u8,
};

const Self = @This();

allocator: Allocator,
diagnostics: std.ArrayList(Diagnostics),
has_errors: bool = false,

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .diagnostics = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.diagnostics.deinit(self.allocator);
}

pub fn report(self: *Self, severity: Severity, loc: Location, message: []const u8) !void {
    try self.diagnostics.append(self.allocator, .{
        .severity = severity,
        .line = loc.line,
        .column = loc.column,
        .message = message,
    });
    self.has_errors = true;
}

pub fn render(self: *Self, io: Io, filename: []const u8, source: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var writer = Io.File.stderr().writer(io, &buf);
    const stderr = &writer.interface;

    for (self.diagnostics.items) |d| {
        const ansi_code: usize = switch (d.severity) {
            .@"error" => 31,
            .warning => 35,
            .note => 90,
        };
        try stderr.print("\x1b[1m{s}:{d}:{d}: \x1b[{d}m{s}:\x1b[39m {s}\x1b[0m\n", .{ filename, d.line, d.column, ansi_code, @tagName(d.severity), d.message });

        var line_it = std.mem.splitScalar(u8, source, '\n');
        var current_line: usize = 1;
        while (line_it.next()) |line_text| : (current_line += 1) {
            if (current_line == d.line) {
                try stderr.print(" {s}\n", .{line_text});
                try stderr.writeAll(" ");
                for (0..d.column - 1) |_|
                    try stderr.writeAll(" ");
                try stderr.print("\x1b[32m^\x1b[0m\n", .{});
                break;
            }
        }
    }
    try stderr.flush();
}
