const std = @import("std");

pub const Id = enum(u32) {
    unused = std.math.maxInt(u32),
    generated = std.math.maxInt(u32) - 1,
    _,
};

pub const Location = struct {
    id: Id = .unused,
    byte_offset: u32 = 0,
    line: u32 = 0,

    pub fn eql(a: Location, b: Location) bool {
        return a.id == b.id and a.byte_offset == b.byte_offset and a.line == b.line;
    }

    pub fn expand(loc: Location, comp: *const @import("Compilation.zig")) ExpandedLocation {
        _ = loc;
        _ = comp;
        return undefined;
    }
};

pub const ExpandedLocation = struct {
    path: []const u8,
    line: []const u8,
    line_no: u32,
    col: u32,
    width: u32,
};

const Source = @This();

path: []const u8,
buf: []const u8,
id: Id,
