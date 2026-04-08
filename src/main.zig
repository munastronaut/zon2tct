const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Lexer = @import("Lexer.zig");

var stdout_buf: [4096]u8 align(std.heap.page_size_min) = undefined;

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

        defer if (std.fs.path.isAbsolute(path)) dir.close(io);

        const b = try dir.readFileAlloc(io, path, allocator, .limited(std.math.maxInt(u32)));
        break :blk try allocator.dupeSentinel(u8, b, 0);
    };

    var stdout_w = Io.File.stdout().writer(init.io, &stdout_buf);

    const clicolor_force = if (init.environ_map.get("CLICOLOR_FORCE")) |v|
        !std.mem.eql(u8, v, "0")
    else
        false;

    const no_color = init.environ_map.contains("NO_COLOR");

    const term_mode = try Io.Terminal.Mode.detect(
        init.io,
        stdout_w.file,
        no_color,
        clicolor_force,
    );

    const t: Io.Terminal = .{
        .mode = term_mode,
        .writer = &stdout_w.interface,
    };

    var lexer = Lexer.init(file);
    var tok_count: usize = 1;
    while (true) : (tok_count += 1) {
        const tok = lexer.next();
        try t.setColor(.bold);
        try t.writer.print("token {d}\n", .{tok_count});
        try t.setColor(.reset);
        try t.setColor(.dim);
        try t.writer.writeAll("├─");
        try t.setColor(.reset);
        try t.setColor(.bold);
        try t.writer.writeAll(" tag:");
        try t.setColor(.reset);
        try t.writer.print(" {s}\n", .{@tagName(tok.id)});
        try t.setColor(.dim);
        try t.writer.writeAll("╰─");
        try t.setColor(.reset);
        try t.setColor(.bold);
        try t.writer.writeAll(" lexeme: '");
        try t.setColor(.reset);
        try t.writer.print("{s}", .{lexer.src[tok.loc.start..tok.loc.end]});
        try t.setColor(.bold);
        try t.writer.writeAll("'\n\n");
        try t.setColor(.reset);
        if (tok.id == .eof) break;
    }
    try t.writer.flush();
}
