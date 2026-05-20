const std = @import("std");
const Io = std.Io;

pub const ErrorBundle = @import("ErrorBundle.zig");
pub const Ir = @import("Tree.zig");
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
