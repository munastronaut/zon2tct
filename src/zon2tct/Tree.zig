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

        if (!std.debug.runtime_safety) {
            assert(@sizeOf(Data) == 8);
        }
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

pub fn tokenStart(tree: *const Tree, token_index: TokenIndex) ByteOffset {
    return tree.tokens.items(.start)[token_index];
}

pub fn parse(allocator: Allocator, src: [:0]const u8) Allocator.Error!Tree {
    var toks = Tree.TokenList{};
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

pub fn deinit(tree: *Tree, allocator: Allocator) void {
    tree.tokens.deinit(allocator);
    tree.nodes.deinit(allocator);
    allocator.free(tree.extra_data);
    tree.* = undefined;
}

pub fn parseTokens(
    allocator: Allocator,
    src: [:0]const u8,
    tokens: TokenList.Slice,
) Allocator.Error!Tree {
    var parser: Parse = .{
        .allocator = allocator,
        .src = src,
        .tokens = tokens,
        .tok_i = 0,
        .nodes = .empty,
        .extra_data = .empty,
        .scratch = .empty,
    };
    defer parser.nodes.deinit(allocator);
    defer parser.extra_data.deinit(allocator);
    defer parser.scratch.deinit(allocator);

    const extra_data = try parser.extra_data.toOwnedSlice(allocator);
    errdefer allocator.free(extra_data);

    return .{
        .src = src,
        .tokens = tokens,
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = extra_data,
    };
}

pub fn tokenLocation(tree: Tree, start_offset: ByteOffset, token_index: TokenIndex) Location {
    var loc: Location = .{
        .line = 1,
        .column = 1,
        .line_start = start_offset,
        .line_end = tree.src.len,
    };
    const tok_start = tree.tokenStart(token_index);

    while (std.mem.findScalarPos(u8, tree.src, loc.line_start, '\n')) |i| {
        if (i >= tok_start) break;
        loc.line += 1;
        loc.line_start = i + 1;
    }

    const offset = loc.line_start;
    for (tree.src[offset..], 0..) |c, i| {
        if (i + offset == tok_start) {
            loc.line_end = i + offset;
            while (loc.line_end < tree.src.len and tree.src[loc.line_end] != '\n')
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
