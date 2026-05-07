const Parse = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Tree = @import("Tree.zig");
const Node = Tree.Node;
const Token = Tree.Token;
const TokenIndex = Tree.TokenIndex;

pub const Error = error{ParseError} || Allocator.Error;

gpa: Allocator,
src: []const u8,
tokens: Tree.TokenList.Slice,
tok_i: TokenIndex,
errors: std.ArrayList(Tree.Error),
nodes: Tree.NodeList,
extra_data: std.ArrayList(u32),
scratch: std.ArrayList(Node.Index),

fn tokenId(p: *const Parse, tok_idx: TokenIndex) Token.Id {
    return p.tokens.items(.id)[tok_idx];
}

fn tokenStart(p: *const Parse, tok_idx: TokenIndex) Tree.ByteOffset {
    return p.tokens.items(.start)[tok_idx];
}

fn warn(p: *Parse, id: Tree.Error.Id) Error {
    @branchHint(.cold);
    try p.warnMsg(.{ .id = id, .token = p.tok_i });
}

fn warnExpected(p: *Parse, expected_token: Token.Id) Allocator.Error!void {
    @branchHint(.cold);
    try p.warnMsg(.{
        .id = .expected_token,
        .token = p.tok_i,
        .extra = .{ .expected_id = expected_token },
    });
}

fn warnMsg(p: *Parse, msg: Tree.Error) Allocator.Error!void {
    @branchHint(.cold);
    switch (msg.id) {
        .expected_expr,
        .expected_token,
        .expected_prefix_expr,
        => if (msg.token != 0 and p.tokensOnSameLine(msg.token - 1, msg.token)) {
            var copy = msg;
            copy.token_is_prev = true;
            copy.token -= 1;
            return p.errors.append(p.gpa, copy);
        },
        //else => {},
    }
    try p.errors.append(p.gpa, msg);
}

fn fail(p: *Parse, id: Tree.Error.Id) Error {
    @branchHint(.cold);
    return p.failMsg(.{ .id = id, .token = p.tok_i });
}

fn failExpected(p: *Parse, expected_token: Token.Id) Error {
    @branchHint(.cold);
    return p.failMsg(.{
        .id = .expected_token,
        .token = p.tok_i,
        .extra = .{ .expected_id = expected_token },
    });
}

fn failMsg(p: *Parse, msg: Tree.Error) Error {
    @branchHint(.cold);
    try p.warnMsg(msg);
    return Error.ParseError;
}

pub fn parse(p: *Parse) !void {
    p.nodes.appendAssumeCapacity(.{
        .id = .root,
        .main_tok = 0,
        .data = undefined,
    });
    const node_idx = p.expectValue() catch |err| switch (err) {
        error.ParseError => {
            assert(p.errors.items.len > 0);
            return;
        },
        else => |e| return e,
    };
    if (p.tokenId(p.tok_i) != .eof) try p.warnExpected(.eof);
    p.nodes.items(.data)[0] = .{ .node = node_idx };
}

fn parseValue(p: *Parse) Error!?Node.Index {
    switch (p.tokenId(p.tok_i)) {
        .char_literal => return try p.addNode(.{
            .id = .char_literal,
            .main_tok = p.nextToken(),
            .data = undefined,
        }),
        .number_literal => return try p.addNode(.{
            .id = .number_literal,
            .main_tok = p.nextToken(),
            .data = undefined,
        }),
        .string_literal => return try p.addNode(.{
            .id = .string_literal,
            .main_tok = p.nextToken(),
            .data = undefined,
        }),
        .multiline_string_literal_line => {
            const first_line = p.nextToken();
            while (p.tokenId(p.tok_i) == .multiline_string_literal_line)
                p.tok_i += 1;

            return try p.addNode(.{
                .id = .multiline_string_literal,
                .main_tok = first_line,
                .data = .{ .token_and_token = .{ first_line, p.tok_i - 1 } },
            });
        },
        .identifier => return try p.addNode(.{
            .id = .identifier,
            .main_tok = p.nextToken(),
            .data = undefined,
        }),
        .period => switch (p.tokenId(p.tok_i + 1)) {
            .identifier => {
                p.tok_i += 1;
                return try p.addNode(.{
                    .id = .enum_literal,
                    .main_tok = p.nextToken(),
                    .data = undefined,
                });
            },
            .l_brace => {
                const l_brace = p.tok_i + 1;
                p.tok_i = l_brace + 1;
                // TODO
            },
        },
    }
}

fn expectValue(p: *Parse) Error!Node.Index {
    return try p.parseValue() orelse p.fail(.expected_expr);
}

fn parsePrefixExpr(p: *Parse) Error!?Node.Index {
    const id: Node.Id = switch (p.tokenId(p.tok_i)) {
        .minus => .negation,
    };
    return try p.addNode(.{
        .id = id,
        .main_tok = p.nextToken(),
        .data = .{ .node = try p.expectPrefixExpr() },
    });
}

fn expectPrefixExpr(p: *Parse) Error!Node.Index {
    return try p.parsePrefixExpr() orelse return p.fail(.expected_prefix_expr);
}

fn parseFieldInit(p: *Parse) Error!?Node.Index {
    if (p.eatTokens(&.{ .period, .identifier, .equal })) |_|
        return try p.expectValue();

    return null;
}

fn expectFieldInit(p: *Parse) Error!?Node.Index {
    if (p.eatTokens(&.{ .period, .identifier, .equal })) |_|
        return try p.expectValue();

    return p.fail(.expected_initializer);
}

fn addNode(p: *Parse, elem: Tree.Node) Allocator.Error!Node.Index {
    const res: Node.Index = @enumFromInt(p.nodes.len);
    try p.nodes.append(p.gpa, elem);
    return res;
}

fn tokensOnSameLine(p: *Parse, token1: TokenIndex, token2: TokenIndex) bool {
    return std.mem.findScalar(u8, p.src[p.tokenStart(token1)..p.tokenStart(token2)], '\n') != null;
}

fn eatToken(p: *Parse, id: Token.Id) ?TokenIndex {
    return if (p.tokenId(p.tok_i) == id) p.nextToken() else null;
}

fn eatTokens(p: *Parse, ids: []const Token.Id) ?TokenIndex {
    const avail_ids = p.tokens.items(.id)[p.tok_i..];
    if (!std.mem.startsWith(Token.Id, avail_ids, ids)) return null;
    const result = p.tok_i;
    p.tok_i += @intCast(ids.len);
    return result;
}

fn nextToken(p: *Parse) TokenIndex {
    const res = p.tok_i;
    p.tok_i += 1;
    return res;
}
