const std = @import("std");

pub const Token = struct {
    id: Id,
    span: Span,

    /// Type of the token.
    pub const Id = enum {
        invalid,
        equal,
        eof,
        whitespace,
        newline,
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
        line_comment,
        doc_comment,
    };

    /// Location of the token or lexeme.
    pub const Span = struct {
        start: usize,
        end: usize,
    };
};

const Self = @This();

buf: [:0]const u8,
idx: usize,

/// `buf` is the content of the file.
pub fn init(buf: [:0]const u8) Self {
    return .{
        .buf = buf,
        .idx = if (std.mem.startsWith(u8, buf, "\xef\xbb\xbf")) 3 else 0,
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
    invalid,
};

/// Lexes on-demand, returns a token.
pub fn next(self: *Self) Token {
    var result: Token = .{
        .id = undefined,
        .span = .{ .start = self.idx, .end = undefined },
    };

    //@setRuntimeSafety(false);
    // Handle numbers and strings soon (also multiline strings!)
    state: switch (State.start) {
        .start => switch (self.buf[self.idx]) {
            0 => if (self.idx == self.buf.len) {
                return .{
                    .id = .eof,
                    .span = .{ .start = self.idx, .end = self.idx },
                };
            } else {
                continue :state .invalid;
            },
            ' ', '\n', '\r', '\t' => {
                self.idx += 1;
                result.span.start = self.idx;
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
            '=' => {
                result.id = .equal;
                self.idx += 1;
            },
            '\\' => {
                result.id = .multiline_string_literal_line;
                continue :state .backslash;
            },
            ',' => {
                result.id = .comma;
                self.idx += 1;
            },
            '{' => {
                result.id = .l_brace;
                self.idx += 1;
            },
            '}' => {
                result.id = .r_brace;
                self.idx += 1;
            },
            '.' => {
                result.id = .period;
                self.idx += 1;
            },
            '-' => {
                result.id = .minus;
                self.idx += 1;
            },
            '+' => {
                result.id = .plus;
                self.idx += 1;
            },
            '/' => continue :state .slash,
            '0'...'9' => {
                result.id = .number_literal;
                self.idx += 1;
                continue :state .int;
            },
            else => continue :state .invalid,
        },

        .invalid => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx == self.buf.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                else => continue :state .invalid,
            }
        },

        .identifier => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                else => {},
            }
        },

        .backslash => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => result.id = .invalid,
                '\\' => continue :state .multiline_string_literal_line,
                '\n' => result.id = .invalid,
                else => continue :state .invalid,
            }
        },

        .string_literal => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx == self.buf.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                '"' => self.idx += 1,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .string_literal,
            }
        },
        .string_literal_backslash => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0, '\n' => result.id = .invalid,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .string_literal,
            }
        },

        .char_literal => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx == self.buf.len) {
                    result.id = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => result.id = .invalid,
                '\\' => continue :state .char_literal_backslash,
                '\'' => self.idx += 1,
                0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .char_literal,
            }
        },
        .char_literal_backslash => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx == self.buf.len) {
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
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx != self.buf.len) {
                    continue :state .invalid;
                },
                '\n' => {},
                '\r' => if (self.buf[self.idx + 1] != '\n') {
                    continue :state .invalid;
                },
                0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                else => continue :state .multiline_string_literal_line,
            }
        },

        .slash => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                '/' => continue :state .line_comment_start,
                else => continue :state .invalid,
            }
        },

        .line_comment_start => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx != self.buf.len) {
                    continue :state .invalid;
                } else return .{
                    .id = .eof,
                    .span = .{ .start = self.idx, .end = self.idx },
                },
                '/' => continue :state .doc_comment_start,
                else => continue :state .line_comment,
            }
        },
        .doc_comment_start => {},
        .line_comment => {},
        .doc_comment => {},

        .int => switch (self.buf[self.idx]) {
            '.' => continue :state .int_period,
            '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                self.idx += 1;
                continue :state .int;
            },
            'e', 'E', 'p', 'P' => continue :state .int_exponent,
            else => {},
        },
        .int_exponent => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                '-', '+' => {
                    self.idx += 1;
                    continue :state .float;
                },
                else => continue :state .int,
            }
        },
        .int_period => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    self.idx += 1;
                    continue :state .float;
                },
                'e', 'E', 'p', 'P' => continue :state .float_exponent,
                else => self.idx -= 1,
            }
        },
        .float => switch (self.buf[self.idx]) {
            '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                self.idx += 1;
                continue :state .float;
            },
            'e', 'E', 'p', 'P' => continue :state .float_exponent,
            else => {},
        },
        .float_exponent => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                '-', '+' => {
                    self.idx += 1;
                    continue :state .float;
                },
                else => continue :state .float,
            }
        },

        .expect_newline => {
            self.idx += 1;
            switch (self.buf[self.idx]) {
                0 => if (self.idx != self.buf.len) {
                    continue :state .invalid;
                } else {
                    result.id = .invalid;
                },
                '\n' => {
                    self.idx += 1;
                    result.span.start = self.idx;
                    continue :state .start;
                },
                else => continue :state .invalid,
            }
        },
    }

    result.span.end = self.idx;
    return result;
}

test "fields and values" {
    try testTokenize(".field = 42", &.{
        .period,
        .identifier,
        .equal,
        .number_literal,
    });
    try testTokenize(
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
    try testTokenize(
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
    try testTokenize(
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

test "newline in char literal" {
    try testTokenize(
        \\'
        \\'
    , &.{ .invalid, .invalid });
}

test "newline in string literal" {
    try testTokenize(
        \\"
        \\"
    , &.{ .invalid, .invalid });
}

fn testTokenize(src: [:0]const u8, tok_ids: []const Token.Id) !void {
    var tokenizer = Self.init(src);
    for (tok_ids) |tok_id| {
        const tok = tokenizer.next();
        try std.testing.expectEqual(tok_id, tok.id);
    }
    const last_tok = tokenizer.next();
    try std.testing.expectEqual(Token.Id.eof, last_tok.id);
    try std.testing.expectEqual(src.len, last_tok.span.start);
    try std.testing.expectEqual(src.len, last_tok.span.end);
}
