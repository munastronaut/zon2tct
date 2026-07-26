const Lexer = @This();

const std = @import("std");

pub const Token = struct {
    id: Id,
    loc: Loc,

    /// Type of the token.
    pub const Id = enum {
        invalid,
        equal,
        eof,
        period,
        plus,
        minus,
        comma,
        identifier,
        number_literal,
        l_paren,
        r_paren,
        l_brace,
        r_brace,
        string_literal,
        multiline_string_literal_line,
        char_literal,

        pub fn lexeme(id: Id) ?[]const u8 {
            return switch (id) {
                .invalid,
                .identifier,
                .string_literal,
                .multiline_string_literal_line,
                .char_literal,
                .eof,
                .number_literal,
                => null,

                // zig fmt: off
                .equal   => "=",
                .period  => ".",
                .plus    => "+",
                .minus   => "-",
                .comma   => ",",
                .l_paren => "(",
                .r_paren => ")",
                .l_brace => "{",
                .r_brace => "}",
                // zig fmt: on
            };
        }

        pub fn symbol(id: Id) []const u8 {
            return id.lexeme() orelse switch (id) {
                // zig fmt: off
                .invalid                       => "invalid token",
                .identifier                    => "an identifier",
                .string_literal                => "a string literal",
                .multiline_string_literal_line => "a multiline string literal",
                .char_literal                  => "a character literal",
                .eof                           => "EOF",
                .number_literal                => "a number literal",
                else                           => unreachable,
                // zig fmt: on
            };
        }
    };

    /// Location of the token or lexeme.
    // There won't be a file larger than 4 gibibytes, right? Right?
    pub const Loc = struct {
        start: u32,
        end: u32,
    };
};

src: [:0]const u8,
idx: u32,

/// `src` is the content of the file.
pub fn init(src: [:0]const u8) Lexer {
    return .{
        .src = src,
        .idx = if (std.mem.startsWith(u8, src, "\xef\xbb\xbf")) 3 else 0,
    };
}

const State = enum {
    start,
    expect_newline,
    string_literal,
    string_literal_backslash,
    multiline_string_literal_line,
    char_literal,
    char_literal_backslash,
    identifier,
    int,
    int_period,
    int_exponent,
    float,
    float_exponent,
    slash,
    line_comment_start,
    line_comment,
    doc_comment_start,
    doc_comment,
    backslash,
    saw_at_sign,
    invalid,
};

/// Lexes on-demand, returns a token.
pub fn next(l: *Lexer) Token {
    var result: Token = .{
        .id = undefined,
        .loc = .{ .start = l.idx, .end = undefined },
    };

    @setRuntimeSafety(false);
    state: switch (State.start) {
        .start => switch (l.src[l.idx]) {
            0 => if (l.idx == l.src.len) {
                return .{
                    .id = .eof,
                    .loc = .{ .start = l.idx, .end = l.idx },
                };
            } else {
                continue :state .invalid;
            },
            ' ', '\n', '\r', '\t' => {
                l.idx += 1;
                result.loc.start = l.idx;
                continue :state .start;
            },
            '"' => {
                result.id = .string_literal;
                continue :state .string_literal;
            },
            '\'' => {
                result.id = .char_literal;
                continue :state .char_literal;
            },
            'a'...'z', 'A'...'Z', '_' => {
                result.id = .identifier;
                continue :state .identifier;
            },
            '@' => continue :state .saw_at_sign,
            '=' => {
                result.id = .equal;
                l.idx += 1;
            },
            '\\' => {
                result.id = .multiline_string_literal_line;
                continue :state .backslash;
            },
            ',' => {
                result.id = .comma;
                l.idx += 1;
            },
            '{' => {
                result.id = .l_brace;
                l.idx += 1;
            },
            '}' => {
                result.id = .r_brace;
                l.idx += 1;
            },
            '.' => {
                result.id = .period;
                l.idx += 1;
            },
            '-' => {
                result.id = .minus;
                l.idx += 1;
            },
            '+' => {
                result.id = .plus;
                l.idx += 1;
            },
            '/' => continue :state .slash,
            '0'...'9' => {
                result.id = .number_literal;
                l.idx += 1;
                continue :state .int;
            },
            else => continue :state .invalid,
        },

        .invalid => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx == l.src.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                else => continue :state .invalid,
            }
        },

        .saw_at_sign => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0, '\n' => result.id = .invalid,
                '"' => {
                    result.id = .identifier;
                    continue :state .string_literal;
                },
                else => continue :state .invalid,
            }
        },

        .identifier => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                else => {},
            }
        },

        .backslash => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => result.id = .invalid,
                '\\' => continue :state .multiline_string_literal_line,
                '\n' => result.id = .invalid,
                else => continue :state .invalid,
            }
        },

        .string_literal => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx == l.src.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                '\\' => continue :state .string_literal_backslash,
                '"' => l.idx += 1,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .string_literal,
            }
        },
        .string_literal_backslash => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0, '\n' => result.id = .invalid,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .string_literal,
            }
        },

        .char_literal => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx == l.src.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                '\\' => continue :state .char_literal_backslash,
                '\'' => l.idx += 1,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .char_literal,
            }
        },
        .char_literal_backslash => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx == l.src.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .char_literal,
            }
        },

        .multiline_string_literal_line => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx != l.src.len) {
                    continue :state .invalid;
                },
                '\n' => {},
                '\r' => if (l.src[l.idx + 1] != '\n') {
                    continue :state .invalid;
                },
                0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .multiline_string_literal_line,
            }
        },

        .slash => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                '/' => continue :state .line_comment_start,
                else => continue :state .invalid,
            }
        },

        .line_comment_start => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx != l.src.len) {
                    continue :state .invalid;
                } else return .{
                    .id = .eof,
                    .loc = .{ .start = l.idx, .end = l.idx },
                },
                '\n' => {
                    l.idx += 1;
                    result.loc.start = l.idx;
                    continue :state .start;
                },
                '/' => continue :state .doc_comment_start,
                '\r' => continue :state .expect_newline,
                0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .line_comment,
            }
        },
        .doc_comment_start => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx != l.src.len) {
                    continue :state .invalid;
                } else return .{
                    .id = .eof,
                    .loc = .{ .start = l.idx, .end = l.idx },
                },
                '\n' => {
                    l.idx += 1;
                    result.loc.start = l.idx;
                    continue :state .start;
                },
                '\r' => continue :state .expect_newline,
                0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .line_comment,
            }
        },
        .line_comment => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx != l.src.len) {
                    continue :state .invalid;
                } else return .{
                    .id = .eof,
                    .loc = .{ .start = l.idx, .end = l.idx },
                },
                '\n' => {
                    l.idx += 1;
                    result.loc.start = l.idx;
                    continue :state .start;
                },
                '\r' => continue :state .expect_newline,
                0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .line_comment,
            }
        },
        .doc_comment => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx != l.src.len) {
                    continue :state .invalid;
                } else return .{
                    .id = .eof,
                    .loc = .{ .start = l.idx, .end = l.idx },
                },
                '\n' => {
                    l.idx += 1;
                    result.loc.start = l.idx;
                    continue :state .start;
                },
                '\r' => continue :state .expect_newline,
                0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .doc_comment,
            }
        },

        .int => switch (l.src[l.idx]) {
            '.' => continue :state .int_period,
            '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                l.idx += 1;
                continue :state .int;
            },
            'e', 'E', 'p', 'P' => continue :state .int_exponent,
            else => {},
        },
        .int_exponent => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                '-', '+' => {
                    l.idx += 1;
                    continue :state .float;
                },
                else => continue :state .int,
            }
        },
        .int_period => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    l.idx += 1;
                    continue :state .float;
                },
                'e', 'E', 'p', 'P' => continue :state .float_exponent,
                else => l.idx -= 1,
            }
        },
        .float => switch (l.src[l.idx]) {
            '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                l.idx += 1;
                continue :state .float;
            },
            'e', 'E', 'p', 'P' => continue :state .float_exponent,
            else => {},
        },
        .float_exponent => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                '-', '+' => {
                    l.idx += 1;
                    continue :state .float;
                },
                else => continue :state .float,
            }
        },

        .expect_newline => {
            l.idx += 1;
            switch (l.src[l.idx]) {
                0 => if (l.idx != l.src.len) {
                    continue :state .invalid;
                } else {
                    result.id = .invalid;
                },
                '\n' => {
                    l.idx += 1;
                    result.loc.start = l.idx;
                    continue :state .start;
                },
                else => continue :state .invalid,
            }
        },
    }

    result.loc.end = l.idx;
    return result;
}

test "fields and values" {
    try testLex(".field = 42", &.{
        .period,
        .identifier,
        .equal,
        .number_literal,
    });
    try testLex(
        \\.foo = 42,
        \\.bar = 69,
    , &.{
        .period,
        .identifier,
        .equal,
        .number_literal,
        .comma,
        .period,
        .identifier,
        .equal,
        .number_literal,
        .comma,
    });
}

test "structs" {
    try testLex(
        \\.{
        \\    .foo = 42,
        \\}
    , &.{
        .period,
        .l_brace,
        .period,
        .identifier,
        .equal,
        .number_literal,
        .comma,
        .r_brace,
    });
    try testLex(
        \\.{
        \\    .foo = 69,
        \\    .field = .{
        \\        .bar = 42,
        \\    },
        \\}
    , &.{
        .period,
        .l_brace,
        .period,
        .identifier,
        .equal,
        .number_literal,
        .comma,
        .period,
        .identifier,
        .equal,
        .period,
        .l_brace,
        .period,
        .identifier,
        .equal,
        .number_literal,
        .comma,
        .r_brace,
        .comma,
        .r_brace,
    });
}

test "disambiguates multiline strings" {
    try testLex(
        \\\\Testing,
        \\\\Qux,
    , &.{ .multiline_string_literal_line, .multiline_string_literal_line });
}

test "char literal" {
    try testLex(".foo = 't'", &.{ .period, .identifier, .equal, .char_literal });
}

test "string literal" {
    try testLex(".foo = \"test\"", &.{ .period, .identifier, .equal, .string_literal });
}

test "newline in char literal" {
    try testLex(
        \\'
        \\'
    , &.{ .invalid, .invalid });
}

test "newline in string literal" {
    try testLex(
        \\"
        \\"
    , &.{ .invalid, .invalid });
}

fn testLex(src: [:0]const u8, tok_ids: []const Token.Id) !void {
    var lexer = Lexer.init(src);
    for (tok_ids) |tok_id| {
        const tok = lexer.next();
        try std.testing.expectEqual(tok_id, tok.id);
    }
    const last_tok = lexer.next();
    try std.testing.expectEqual(Token.Id.eof, last_tok.id);
    try std.testing.expectEqual(src.len, last_tok.loc.start);
    try std.testing.expectEqual(src.len, last_tok.loc.end);
}
