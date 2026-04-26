const std = @import("std");
const Allocator = std.mem.Allocator;

const Diagnostics = @import("../zon2tct.zig").Diagnostics;

const Compilation = @This();

gpa: Allocator,
arena: Allocator,
io: std.Io,
cwd: std.Io.Dir,
diagnostics: *Diagnostics,

pub const testing: Compilation = .{
    .gpa = std.testing.allocator,
    .arena = undefined,
    .io = std.testing.io,
    .cwd = undefined,
    .diagnostics = undefined,
};
