//! This namespace copies much of `std.zig`.

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = mem.Allocator;
const Writer = Io.Writer;

pub const ErrorBundle = @import("zon2tct/ErrorBundle.zig");
pub const Ir = @import("zon2tct/Ir.zig");
pub const IrGen = @import("zon2tct/IrGen.zig");
pub const Lexer = @import("zon2tct/Lexer.zig");
pub const Parse = @import("zon2tct/Parse.zig");
pub const Token = Lexer.Token;
pub const Tree = @import("zon2tct/Tree.zig");

pub const max_src_size = std.math.maxInt(u32);

pub const Color = std.zig.Color;

pub const findLineColumn = std.zig.findLineColumn;

pub fn fmtString(bytes: []const u8) std.fmt.Alt([]const u8, stringEscape) {
    return .{ .data = bytes };
}

pub fn stringEscape(bytes: []const u8, w: *Writer) Writer.Error!void {
    var view = std.unicode.Utf8View.init(bytes) catch |err| switch (err) {
        error.InvalidUtf8 => {
            for (bytes) |byte|
                try w.print("\\x:{x:0>2}", .{byte});
            return;
        },
    };

    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| switch (codepoint) {
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        '\\' => try w.writeAll("\\\\"),
        '"' => try w.writeAll("\\\""),
        '/' => try w.writeAll("\\/"),
        0...8,
        11,
        12,
        14...0x1f,
        0x7f,
        0x2028,
        0x2029,
        => try w.print("\\u{{{x}}}", .{codepoint}),
        else => {
            var out: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &out) catch unreachable;
            try w.writeAll(out[0..len]);
        },
    };
}

pub fn isValidId(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    for (bytes, 0..) |c, i| {
        switch (c) {
            '_', 'a'...'z', 'A'...'Z' => {},
            '0'...'9' => if (i == 0) return false,
            else => return false,
        }
    }
    return true;
}

pub const readSourceFileToEndAlloc = std.zig.readSourceFileToEndAlloc;

pub const EnvVar = enum {
    NO_COLOR,
    CLICOLOR_FORCE,

    pub fn isSet(ev: EnvVar, map: *const std.process.Environ.Map) bool {
        return map.contains(@tagName(ev));
    }
};

test {
    _ = ErrorBundle;
    _ = Ir;
    _ = IrGen;
    _ = Lexer;
    _ = Parse;
    _ = Token;
    _ = Tree;
}
