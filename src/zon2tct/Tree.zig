const Tree = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Lexer = @import("Lexer.zig");
const Token = Lexer.Token;
const Parse = @import("Parse.zig");

src: [:0]const u8,

tokens: TokenList.Slice,
nodes: NodeList.Slice,
extra_data: []u32,

errors: []const Error,

pub const TokenList = std.MultiArrayList(struct {
    id: Token.Id,
    start: u32,
});
pub const NodeList = std.MultiArrayList(Node);

pub const ByteOffset = u32;

pub const TokenIndex = u32;
pub const OptionalTokenIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn unwrap(oti: OptionalTokenIndex) ?TokenIndex {
        return if (oti == .none) null else @intFromEnum(oti);
    }

    pub fn fromToken(ti: TokenIndex) OptionalTokenIndex {
        return @enumFromInt(ti);
    }

    pub fn fromOptional(oti: ?TokenIndex) OptionalTokenIndex {
        return if (oti) |ti| @enumFromInt(ti) else .none;
    }
};

pub const ExtraIndex = enum(u32) {
    _,
};

pub const Node = struct {
    id: Id,
    main_tok: TokenIndex,
    data: Data,

    pub const Index = enum(u32) {
        root = 0,
        _,

        pub fn toOptional(i: Index) OptionalIndex {
            const res: OptionalIndex = @enumFromInt(@intFromEnum(i));
            assert(res != .none);
            return res;
        }
    };

    pub const OptionalIndex = enum(u32) {
        root = 0,
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(oi: OptionalIndex) ?Index {
            return if (oi == .none) null else @enumFromInt(@intFromEnum(oi));
        }

        pub fn fromOptional(oi: ?Index) OptionalIndex {
            return if (oi) |i| i.toOptional() else .none;
        }
    };

    comptime {
        assert(@sizeOf(Id) == 1);

        if (!std.debug.runtime_safety)
            assert(@sizeOf(Data) == 8);
    }

    pub const Id = enum {
        root,
        negation,
        char_literal,
        number_literal,
        identifier,
        enum_literal,
        string_literal,
        multiline_string_literal,
        //field_assignment,
        //struct_init,
        //array_init,
    };

    pub const Data = union {
        none: void,
        node: Index,
        token_and_token: struct { TokenIndex, TokenIndex },
        extra_range: SubRange,
    };

    pub const SubRange = struct {
        start: ExtraIndex,
        end: ExtraIndex,
    };
};

pub const Location = struct {
    line: u32,
    column: u32,
    line_start: u32,
    line_end: u32,
};

pub fn tokenStart(t: *const Tree, tok_idx: TokenIndex) ByteOffset {
    return t.tokens.items(.start)[tok_idx];
}

pub fn tokenId(t: *const Tree, tok_idx: TokenIndex) Token.Id {
    return t.tokens.items(.id)[tok_idx];
}

pub fn parse(gpa: Allocator, src: [:0]const u8) Allocator.Error!Tree {
    var toks: Tree.TokenList = .empty;
    defer toks.deinit(gpa);

    var lexer = Lexer.init(src);
    while (true) {
        const tok = lexer.next();
        try toks.append(gpa, .{
            .id = tok.id,
            .start = tok.loc.start,
        });
        if (tok.id == .eof) break;
    }

    var toks_slice = toks.toOwnedSlice();
    errdefer toks_slice.deinit(gpa);
    return parseTokens(gpa, src, toks_slice);
}

pub fn parseTokens(
    gpa: Allocator,
    src: [:0]const u8,
    tokens: TokenList.Slice,
) Allocator.Error!Tree {
    var p: Parse = .{
        .gpa = gpa,
        .src = src,
        .tokens = tokens,
        .tok_i = 0,
        .errors = .empty,
        .nodes = .empty,
        .extra_data = .empty,
        .scratch = .empty,
    };
    defer p.errors.deinit(gpa);
    defer p.nodes.deinit(gpa);
    defer p.extra_data.deinit(gpa);
    defer p.scratch.deinit(gpa);

    try p.parse();

    try p.extra_data.shrinkToLen(gpa);
    try p.errors.shrinkToLen(gpa);

    return .{
        .src = src,
        .tokens = tokens,
        .nodes = p.nodes.toOwnedSlice(),
        .extra_data = p.extra_data.toOwnedSliceAssert(),
        .errors = p.errors.toOwnedSliceAssert(),
    };
}

pub fn deinit(t: *Tree, gpa: Allocator) void {
    t.tokens.deinit(gpa);
    t.nodes.deinit(gpa);
    gpa.free(t.extra_data);
    gpa.free(t.errors);
    t.* = undefined;
}

pub fn tokenLocation(t: Tree, start_offset: ByteOffset, tok_idx: TokenIndex) Location {
    var loc: Location = .{
        .line = 1,
        .column = 1,
        .line_start = start_offset,
        .line_end = t.src.len,
    };
    const tok_start = t.tokenStart(tok_idx);

    while (std.mem.findScalarPos(u8, t.src, loc.line_start, '\n')) |i| {
        if (i >= tok_start) break;
        loc.line += 1;
        loc.line_start = i + 1;
    }

    const offset = loc.line_start;
    for (t.src[offset..], 0..) |c, i| {
        if (i + offset == tok_start) {
            loc.line_end = i + offset;
            while (loc.line_end < t.src.len and t.src[loc.line_end] != '\n')
                loc.line_end += 1;

            return loc;
        }
        if (c == '\n') {
            loc.line += 1;
            loc.column = 1;
            loc.line_start = i + 1;
        } else {
            loc.column += 1;
        }
    }
    return loc;
}

pub fn tokenSlice(t: Tree, tok_idx: TokenIndex) []const u8 {
    const tok_id = t.tokenId(tok_idx);

    var lexer: Lexer = .{
        .src = t.src,
        .idx = t.tokenStart(tok_idx),
    };
    const tok = lexer.next();
    assert(tok.id == tok_id);
    return t.src[tok.loc.start..tok.loc.end];
}

pub const Error = struct {
    id: Id,
    is_note: bool = false,
    token_is_prev: bool = false,
    token: TokenIndex,
    extra: union {
        none: void,
        expected_id: Token.Id,
        offset: usize,
    } = .{ .none = {} },

    pub const Id = enum {
        expected_expr,
        expected_prefix_expr,
        expected_initializer,
        expected_token,
    };
};
