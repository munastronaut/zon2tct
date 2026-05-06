const Compilation = @This();

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = mem.Allocator;

gpa: Allocator,
arena: Allocator,
io: Io,

pub const FileExt = enum {
    plaintext,
    unknown,
};

pub fn classifyFileExt(filename: []const u8) FileExt {
    if (mem.endsWith(u8, filename, ".zon") or mem.endsWith(u8, filename, ".txt")) {
        return .plaintext;
    } else {
        return .unknown;
    }
}
