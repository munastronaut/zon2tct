const Tree = @This();

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;

const zon2tct = @import("zon2tct.zig");
const Lexer = zon2tct.Lexer;
const Token = zon2tct.Token;
const Parse = zon2tct.Parse;

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

        if (!std.debug.runtime_safety) {
            assert(@sizeOf(Data) == 8);
        }
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
        array_init_dot_two,
        array_init_dot_two_comma,
        array_init_dot,
        array_init_dot_comma,
        struct_init_dot_two,
        struct_init_dot_two_comma,
        struct_init_dot,
        struct_init_dot_comma,
    };

    pub const Data = union {
        none: void,
        node: Index,
        token: TokenIndex,
        node_and_node: struct { Index, Index },
        opt_node_and_opt_node: struct { OptionalIndex, OptionalIndex },
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

pub const Span = struct {
    start: u32,
    end: u32,
    main: u32,
};

pub fn tokenId(tree: *const Tree, tok_idx: TokenIndex) Token.Id {
    return tree.tokens.items(.id)[tok_idx];
}

pub fn tokenStart(tree: *const Tree, tok_idx: TokenIndex) ByteOffset {
    return tree.tokens.items(.start)[tok_idx];
}

pub fn nodeId(tree: *const Tree, node: Node.Index) Node.Id {
    return tree.nodes.items(.id)[@intFromEnum(node)];
}

pub fn nodeMainToken(tree: *const Tree, node: Node.Index) TokenIndex {
    return tree.nodes.items(.main_tok)[@intFromEnum(node)];
}

pub fn nodeData(tree: *const Tree, node: Node.Index) Node.Data {
    return tree.nodes.items(.data)[@intFromEnum(node)];
}

pub fn deinit(tree: *Tree, gpa: Allocator) void {
    tree.tokens.deinit(gpa);
    tree.nodes.deinit(gpa);
    gpa.free(tree.extra_data);
    gpa.free(tree.errors);
    tree.* = undefined;
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

    try p.nodes.ensureTotalCapacity(gpa, (tokens.len + 2) / 2);

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

pub fn errorOffset(tree: Tree, parse_error: Error) u32 {
    return if (parse_error.token_is_prev) @intCast(tree.tokenSlice(parse_error.token).len) else 0;
}

pub fn tokenLocation(tree: Tree, start_offset: ByteOffset, tok_idx: TokenIndex) Location {
    var loc: Location = .{
        .line = 0,
        .column = 0,
        .line_start = start_offset,
        .line_end = tree.src.len,
    };
    const tok_start = tree.tokenStart(tok_idx);

    while (mem.findScalarPos(u8, tree.src, loc.line_start, '\n')) |i| {
        if (i >= tok_start) break;
        loc.line += 1;
        loc.line_start = i + 1;
    }

    const offset = loc.line_start;
    for (tree.src[offset..], 0..) |c, i| {
        if (i + offset == tok_start) {
            loc.line_end = i + offset;
            while (loc.line_end < tree.src.len and tree.src[loc.line_end] != '\n') {
                loc.line_end += 1;
            }
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

pub fn tokenSlice(tree: Tree, tok_idx: TokenIndex) []const u8 {
    const tok_id = tree.tokenId(tok_idx);

    if (tok_id.lexeme()) |lexeme| {
        return lexeme;
    }

    var lexer: Lexer = .{
        .src = tree.src,
        .idx = tree.tokenStart(tok_idx),
    };
    const tok = lexer.next();
    assert(tok.id == tok_id);
    return tree.src[tok.loc.start..tok.loc.end];
}

pub fn extraDataSlice(tree: Tree, range: Node.SubRange, comptime T: type) []const T {
    return @ptrCast(tree.extra_data[@intFromEnum(range.start)..@intFromEnum(range.end)]);
}

fn loadOptionalNodesIntoBuffer(comptime size: usize, buf: *[size]Node.Index, items: [size]Node.OptionalIndex) []Node.Index {
    for (buf, items, 0..) |*node, opt_node, i| {
        node.* = opt_node.unwrap() orelse return buf[0..i];
    }
    return buf[0..];
}

pub fn rootDecls(tree: Tree) []const Node.Index {
    return (&tree.nodes.items(.data)[@intFromEnum(Node.Index.root)].node)[0..1];
}

pub fn renderError(tree: Tree, parse_error: Error, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (parse_error.id) {
        .expected_expr => {
            return w.print("expected expression, found '{s}'", .{
                tree.tokenId(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_prefix_expr => {
            return w.print("expected prefix expression, found '{s}'", .{
                tree.tokenId(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_comma_after_initializer => {
            return w.writeAll("expected ',' after initializer");
        },
        .expected_initializer => {
            return w.writeAll("expected field initializer");
        },
        .expected_token => {
            const found_id = tree.tokenId(parse_error.token + @intFromBool(parse_error.token_is_prev));
            const expected_symbol = parse_error.extra.expected_id.symbol();
            switch (found_id) {
                .invalid => return w.print("expected '{s}', found invalid bytes", .{
                    expected_symbol,
                }),
                else => return w.print("expected '{s}', found '{s}'", .{
                    expected_symbol, found_id.symbol(),
                }),
            }
        },
    }
}

pub fn firstToken(tree: Tree, node: Node.Index) TokenIndex {
    switch (tree.nodeId(node)) {
        .root => return 0,

        .negation,
        .identifier,
        .char_literal,
        .number_literal,
        .string_literal,
        .multiline_string_literal,
        => return tree.nodeMainToken(node),

        .array_init_dot,
        .array_init_dot_comma,
        .array_init_dot_two,
        .array_init_dot_two_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .enum_literal,
        => return tree.nodeMainToken(node) - 1,
    }
}

pub fn lastToken(tree: Tree, node: Node.Index) TokenIndex {
    var n = node;
    var end_offset: u32 = 0;
    while (true) switch (tree.nodeId(n)) {
        .root => return @intCast(tree.tokens.len - 1),

        .negation => n = tree.nodeData(n).node,

        .multiline_string_literal => return tree.nodeData(n).token_and_token[1] + end_offset,

        .char_literal,
        .identifier,
        .number_literal,
        .string_literal,
        .enum_literal,
        => return tree.nodeMainToken(n) + end_offset,

        .array_init_dot, .struct_init_dot => {
            const range = tree.nodeData(n).extra_range;
            assert(range.start != range.end);
            end_offset += 1;
            n = @enumFromInt(tree.extra_data[@intFromEnum(range.end) - 1]);
        },

        .array_init_dot_comma, .struct_init_dot_comma => {
            const range = tree.nodeData(n).extra_range;
            assert(range.start != range.end);
            end_offset += 2;
            n = @enumFromInt(tree.extra_data[@intFromEnum(range.end) - 1]);
        },

        .array_init_dot_two, .struct_init_dot_two => {
            const opt_lhs, const opt_rhs = tree.nodeData(n).opt_node_and_opt_node;
            if (opt_rhs.unwrap()) |rhs| {
                end_offset += 1;
                n = rhs;
            } else if (opt_lhs.unwrap()) |lhs| {
                end_offset += 1;
                n = lhs;
            } else {
                switch (tree.nodeId(n)) {
                    .array_init_dot_two, .struct_init_dot_two => end_offset += 1,
                    else => unreachable,
                }
            }
            return tree.nodeMainToken(n) + end_offset;
        },

        .array_init_dot_two_comma, .struct_init_dot_two_comma => {
            const opt_lhs, const opt_rhs = tree.nodeData(n).opt_node_and_opt_node;
            end_offset += 2;
            if (opt_rhs.unwrap()) |rhs| {
                n = rhs;
            } else if (opt_lhs.unwrap()) |lhs| {
                n = lhs;
            } else {
                unreachable;
            }
        },
    };
}

pub fn tokensOnSameLine(tree: Tree, tok1: TokenIndex, tok2: TokenIndex) bool {
    const src = tree.src[tree.tokenStart(tok1)..tree.tokenStart(tok2)];
    return mem.findScalar(u8, src, '\n') == null;
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
        expected_comma_after_initializer,
        expected_initializer,
        expected_token,
    };
};

pub fn structInitDotTwo(tree: Tree, buf: *[2]Node.Index, node: Node.Index) full.StructInit {
    assert(tree.nodeId(node) == .struct_init_dot_two or tree.nodeId(node) == .struct_init_dot_two_comma);
    const fields = loadOptionalNodesIntoBuffer(2, buf, tree.nodeData(node).opt_node_and_opt_node);
    return .{
        .tree = .{
            .l_brace = tree.nodeMainToken(node),
            .fields = fields,
        },
    };
}

pub fn structInitDot(tree: Tree, node: Node.Index) full.StructInit {
    assert(tree.nodeId(node) == .struct_init_dot or tree.nodeId(node) == .struct_init_dot_comma);
    const fields = tree.extraDataSlice(tree.nodeData(node).extra_range, Node.Index);
    return .{
        .tree = .{
            .l_brace = tree.nodeMainToken(node),
            .fields = fields,
        },
    };
}

pub fn arrayInitDotTwo(tree: Tree, buf: *[2]Node.Index, node: Node.Index) full.ArrayInit {
    assert(tree.nodeId(node) == .array_init_dot_two or tree.nodeId(node) == .array_init_dot_two_comma);
    const elements = loadOptionalNodesIntoBuffer(2, buf, tree.nodeData(node).opt_node_and_opt_node);
    return .{
        .tree = .{
            .l_brace = tree.nodeMainToken(node),
            .elements = elements,
        },
    };
}

pub fn arrayInitDot(tree: Tree, node: Node.Index) full.ArrayInit {
    assert(tree.nodeId(node) == .array_init_dot or tree.nodeId(node) == .array_init_dot_comma);
    const elements = tree.extraDataSlice(tree.nodeData(node).extra_range, Node.Index);
    return .{
        .tree = .{
            .l_brace = tree.nodeMainToken(node),
            .elements = elements,
        },
    };
}

pub fn fullStructInit(tree: Tree, buf: *[2]Node.Index, node: Node.Index) ?full.StructInit {
    return switch (tree.nodeId(node)) {
        .struct_init_dot_two, .struct_init_dot_two_comma => tree.structInitDotTwo(buf, node),
        .struct_init_dot, .struct_init_dot_comma => tree.structInitDot(node),
        else => null,
    };
}

pub fn fullArrayInit(tree: Tree, buf: *[2]Node.Index, node: Node.Index) ?full.ArrayInit {
    return switch (tree.nodeId(node)) {
        .array_init_dot_two, .array_init_dot_two_comma => tree.arrayInitDotTwo(buf, node),
        .array_init_dot, .array_init_dot_comma => tree.arrayInitDot(node),
        else => null,
    };
}

pub const full = struct {
    pub const StructInit = struct {
        tree: Components,

        pub const Components = struct {
            l_brace: TokenIndex,
            fields: []const Node.Index,
        };
    };

    pub const ArrayInit = struct {
        tree: Components,

        pub const Components = struct {
            l_brace: TokenIndex,
            elements: []const Node.Index,
        };
    };
};

pub fn nodeToSpan(tree: *const Tree, node: Node.Index) Span {
    return tree.tokensToSpan(
        tree.firstToken(node),
        tree.lastToken(node),
        tree.nodeMainToken(node),
    );
}

pub fn tokenToSpan(tree: *const Tree, tok: TokenIndex) Span {
    return tree.tokensToSpan(tok, tok, tok);
}

pub fn tokensToSpan(tree: *const Tree, start: TokenIndex, end: TokenIndex, main: TokenIndex) Span {
    var start_tok = start;
    var end_tok = end;

    if (tree.tokensOnSameLine(start, end)) {
        // do nothing
    } else if (tree.tokensOnSameLine(start, main)) {
        end_tok = main;
    } else if (tree.tokensOnSameLine(main, end)) {
        start_tok = main;
    } else {
        start_tok = main;
        end_tok = main;
    }
    const start_off = tree.tokenStart(start_tok);
    const end_off = tree.tokenStart(end_tok) + @as(u32, @intCast(tree.tokenSlice(end_tok).len));
    return .{
        .start = start_off,
        .end = end_off,
        .main = tree.tokenStart(main),
    };
}

test {
    _ = Parse;
}
