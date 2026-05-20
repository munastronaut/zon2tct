const std = @import("std");
const Io = std.Io;
const mem = std.mem;

pub const ErrorBundle = @import("ErrorBundle.zig");
pub const Ir = @import("Ir.zig");
pub const IrGen = @import("IrGen.zig");
pub const Lexer = @import("Lexer.zig");
pub const Parse = @import("Parse.zig");
pub const Token = Lexer.Token;
pub const Tree = @import("Tree.zig");

pub const Color = enum {
    auto,
    off,
    on,

    pub fn terminalMode(color: Color) ?Io.Terminal.Mode {
        return switch (color) {
            .auto => null,
            .on => .escape_codes,
            .off => .no_color,
        };
    }
};

pub const Loc = struct {
    line: usize,
    column: usize,
    src_line: []const u8,

    pub fn eql(a: Loc, b: Loc) bool {
        return a.line == b.line and a.column == b.column and mem.eql(u8, a.src_line, b.src_line);
    }
};

pub fn findLineColumn(src: []const u8, byte_off: usize) Loc {
    var line: usize = 0;
    var column: usize = 0;
    var line_start: usize = 0;
    var i: usize = 0;
    while (i < byte_off) : (i += 1) {
        switch (src[i]) {
            '\n' => {
                line += 1;
                column = 0;
                line_start = i + 1;
            },
            else => column += 1,
        }
    }
    while (i < src.len and src[i] != '\n') {
        i += 1;
    }
    return .{
        .line = line,
        .column = column,
        .src_line = src[line_start..i],
    };
}

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
