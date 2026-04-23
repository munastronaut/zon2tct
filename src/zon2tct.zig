pub const Compilation = @import("zon2tct/Compilation.zig");
pub const Driver = @import("zon2tct/Driver.zig");
pub const Lexer = @import("zon2tct/Lexer.zig");
pub const Tree = @import("zon2tct/Tree.zig");
pub const Parse = @import("zon2tct/Parse.zig");

test {
    _ = @import("zon2tct/Compilation.zig");
    _ = @import("zon2tct/Driver.zig");
    _ = @import("zon2tct/Lexer.zig");
    _ = @import("zon2tct/Tree.zig");
    _ = @import("zon2tct/Parse.zig");
}
