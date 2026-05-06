const Parse = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const zon2tct = @import("../zon2tct.zig");

const Tree = zon2tct.Tree;
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

fn expectExpr(p: *Parse) Error!Node.Index {
    return try p.parseExpr() orelse p.fail(.expected_expr);
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
}

fn parseExpr(p: *Parse) Error!?Node.Index {
    switch (p.tokenId(p.tok_i)) {
        .number_literal => {
            return try p.addNode(.{
                .id = .number_literal,
                .main_tok = p.nextToken(),
            });
        },
    }
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

fn addNode(p: *Parse, elem: Tree.Node) Allocator.Error!Node.Index {
    const res: Node.Index = @enumFromInt(p.nodes.len);
    try p.nodes.append(p.gpa, elem);
    return res;
}

fn tokensOnSameLine(p: *Parse, token1: TokenIndex, token2: TokenIndex) bool {
    return std.mem.findScalar(u8, p.src[p.tokenStart(token1)..p.tokenStart(token2)], '\n') != null;
}

fn nextToken(p: *Parse) TokenIndex {
    const res = p.tok_i;
    p.tok_i += 1;
    return res;
}
