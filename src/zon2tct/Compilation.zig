const std = @import("std");
const Allocator = std.mem.Allocator;

const Compilation = @This();

gpa: Allocator,
arena: Allocator,
io: std.Io,
cwd: std.Io.Dir,
