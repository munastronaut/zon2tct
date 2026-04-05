const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Lexer = @import("Lexer.zig");

const template =
    \\{s}token{s} {d}
    \\├─ {s}tag:{s} {s}
    \\╰─ {s}lexeme:{s} '{s}'
    \\
    \\
;

const bold = "\x1b[1m";
const reset = "\x1b[0m";

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse std.process.fatal("no input file", .{});

    const file = if (std.fs.path.isAbsolute(path)) blk: {
        var f = try std.Io.Dir.openFileAbsolute(init.io, path, .{});
        var r = f.reader(init.io, &.{});
        var reader = &r.interface;
        const b = try reader.readAlloc(allocator, try r.getSize());
        break :blk try allocator.dupeSentinel(u8, b, 0);
    } else blk: {
        const b = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .unlimited);
        break :blk try allocator.dupeSentinel(u8, b, 0);
    };
    std.debug.assert(file[file.len] == 0);

    var lexer = Lexer.init(file);
    var tok_count: usize = 1;
    while (true) : (tok_count += 1) {
        const tok = lexer.next();
        std.debug.print(template, .{
            bold,
            reset,
            tok_count,
            bold,
            reset,
            @tagName(tok.id),
            bold,
            reset,
            lexer.buf[tok.span.start..tok.span.end],
        });
        if (tok.id == .eof) break;
    }
}
