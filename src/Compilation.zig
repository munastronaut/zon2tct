const Compilation = @This();

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = mem.Allocator;

gpa: Allocator,
arena: Allocator,
io: Io,

pub const CreateOptions = struct {
    provided_name: ?[]const u8 = null,
};

pub fn create(gpa: Allocator, arena: Allocator, io: Io, options: CreateOptions) !*Compilation {
    _ = options;
    const comp = try arena.create(Compilation);

    comp.* = .{
        .gpa = gpa,
        .arena = arena,
        .io = io,
    };

    return comp;
}

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
