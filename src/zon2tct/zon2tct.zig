const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = mem.Allocator;
const Writer = Io.Writer;

pub const ErrorBundle = @import("ErrorBundle.zig");
pub const Ir = @import("Ir.zig");
pub const IrGen = @import("IrGen.zig");
pub const Lexer = @import("Lexer.zig");
pub const Parse = @import("Parse.zig");
pub const Token = Lexer.Token;
pub const Tree = @import("Tree.zig");

pub const max_src_size = std.math.maxInt(u32);

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

pub fn fmtString(bytes: []const u8) std.fmt.Alt([]const u8, stringEscape) {
    return .{ .data = bytes };
}

pub fn stringEscape(bytes: []const u8, w: *Writer) Writer.Error!void {
    for (bytes) |byte| switch (byte) {
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        '\\' => try w.writeAll("\\\\"),
        '"' => try w.writeAll("\\\""),
        '\'' => try w.writeByte('\''),
        ' ', '!', '#'...'&', '('...'[', ']'...'~' => try w.writeByte(byte),
        else => if (std.ascii.isControl(byte)) {
            try w.print("\\u{x:0>4}", .{byte});
        } else {
            try w.writeByte(byte);
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

pub fn readSourceFileToEndAlloc(gpa: Allocator, file_reader: *Io.File.Reader) ![:0]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);

    if (file_reader.getSize()) |size| {
        const casted_size = std.math.cast(u32, size) orelse return error.StreamTooLong;
        try buf.ensureTotalCapacity(gpa, casted_size + 1);
    } else |_| {}

    try file_reader.interface.appendRemaining(gpa, &buf, .limited(max_src_size));

    const unsupported_boms = [_][]const u8{
        "\xff\xfe\x00\x00",
        "\xfe\xff\x00\x00",
        "\xfe\xff",
    };
    for (unsupported_boms) |bom| {
        if (mem.startsWith(u8, buf.items, bom)) {
            return error.UnsupportedEncoding;
        }
    }

    if (mem.startsWith(u8, buf.items, "\xff\xfe")) {
        if (buf.items.len % 2 != 0) return error.InvalidEncoding;
        return std.unicode.utf16LeToUtf8AllocZ(gpa, @ptrCast(@alignCast(buf.items))) catch |err| switch (err) {
            error.DanglingSurrogateHalf => error.UnsupportedEncoding,
            error.ExpectedSecondSurrogateHalf => error.UnsupportedEncoding,
            error.UnexpectedSecondSurrogateHalf => error.UnsupportedEncoding,
            else => |e| return e,
        };
    }

    return buf.toOwnedSliceSentinel(gpa, 0);
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
