const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zon2tct = @import("../zon2tct.zig");

const Lexer = zon2tct.Lexer;
const Token = Lexer.Token;

const Parse = zon2tct.Parse;

const Tree = @This();

src: [:0]const u8,

tokens: TokenList.Slice,
nodes: NodeList.Slice,
extra_data: []u32,

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
        number_literal,
        string_literal,
        multiline_string_literal,
        enum_literal,
        negation,
        field_assignment,
        struct_init,
        array_init,
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

pub fn tokenStart(t: *const Tree, token_index: TokenIndex) ByteOffset {
    return t.tokens.items(.start)[token_index];
}

pub fn tokenId(t: *const Tree, token_index: TokenIndex) Token.Id {
    return t.tokens.items(.id)[token_index];
}

pub fn parse(allocator: Allocator, src: [:0]const u8) Allocator.Error!Tree {
    var toks: Tree.TokenList = .empty;
    defer toks.deinit(allocator);

    var lexer = Lexer.init(src);
    while (true) {
        const tok = lexer.next();
        try toks.append(allocator, .{
            .id = tok.id,
            .start = tok.loc.start,
        });
        if (tok.id == .eof) break;
    }

    var toks_slice = toks.toOwnedSlice();
    errdefer toks_slice.deinit(allocator);
    return parseTokens(allocator, src, toks_slice);
}

pub fn deinit(t: *Tree, allocator: Allocator) void {
    t.tokens.deinit(allocator);
    t.nodes.deinit(allocator);
    allocator.free(t.extra_data);
    t.* = undefined;
}

pub fn parseTokens(
    allocator: Allocator,
    src: [:0]const u8,
    tokens: TokenList.Slice,
) Allocator.Error!Tree {
    var p: Parse = .{
        .allocator = allocator,
        .src = src,
        .tokens = tokens,
        .tok_i = 0,
        .nodes = .empty,
        .extra_data = .empty,
        .scratch = .empty,
    };
    defer p.nodes.deinit(allocator);
    defer p.extra_data.deinit(allocator);
    defer p.scratch.deinit(allocator);

    try p.parse();

    const extra_data = try p.extra_data.toOwnedSlice(allocator);
    errdefer allocator.free(extra_data);

    return .{
        .src = src,
        .tokens = tokens,
        .nodes = p.nodes.toOwnedSlice(),
        .extra_data = extra_data,
    };
}

pub fn tokenLocation(t: Tree, start_offset: ByteOffset, token_index: TokenIndex) Location {
    var loc: Location = .{
        .line = 1,
        .column = 1,
        .line_start = start_offset,
        .line_end = t.src.len,
    };
    const tok_start = t.tokenStart(token_index);

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

pub fn tokenSlice(t: Tree, token_index: TokenIndex) []const u8 {
    const tok_id = t.tokenId(token_index);

    var lexer: Lexer = .{
        .src = t.src,
        .idx = t.tokenStart(token_index),
    };
    const tok = lexer.next();
    assert(tok.id == tok_id);
    return t.src[tok.loc.start..tok.loc.end];
}
