const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Lexer = @import("Lexer.zig");

const template =
    \\{s}token {d}{s}
    \\├─ {s}tag:{s} {s}
    \\╰─ {s}lexeme: '{s}{s}{s}'{s}
    \\
    \\
;

const bold = "\x1b[1m";
const reset = "\x1b[0m";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse std.process.fatal("no input file", .{});

    const file = blk: {
        const dir = if (std.fs.path.isAbsolute(path))
            try Io.Dir.openDirAbsolute(io, std.fs.path.dirname(path).?, .{})
        else
            Io.Dir.cwd();

        const b = try dir.readFileAlloc(io, path, allocator, .unlimited);
        break :blk try allocator.dupeSentinel(u8, b, 0);
    };

    var lexer = Lexer.init(file);
    var tok_count: usize = 1;
    while (true) : (tok_count += 1) {
        const tok = lexer.next();
        std.debug.print(template, .{
            bold,
            tok_count,
            reset,
            bold,
            reset,
            @tagName(tok.id),
            bold,
            reset,
            lexer.buf[tok.span.start..tok.span.end],
            bold,
            reset,
        });
        if (tok.id == .eof) break;
    }
}
