const Parse = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const zon2tct = @import("../zon2tct.zig");

const Tree = zon2tct.Tree;
const Node = Tree.Node;
const Token = Tree.Token;
const TokenIndex = Tree.TokenIndex;

pub const Error = error{ParseError} || Allocator.Error;

diag: *zon2tct.Diagnostics,
allocator: Allocator,
src: []const u8,
tokens: Tree.TokenList.Slice,
tok_i: TokenIndex,
nodes: Tree.NodeList,
extra_data: std.ArrayList(u32),
scratch: std.ArrayList(Node.Index),

pub fn parse(p: *Parse) !void {
    p.nodes.appendAssumeCapacity(.{
        .id = .root,
        .main_tok = 0,
        .data = undefined,
    });
}

fn tokenId(p: *const Parse, tok_idx: TokenIndex) Token.Id {
    return p.tokens.items(.id)[tok_idx];
}

fn tokenStart(p: *const Parse, tok_idx: TokenIndex) Tree.ByteOffset {
    return p.tokens.items(.start)[tok_idx];
}

fn expectExpr(p: *Parse) Error!Node.Index {
    return try p.parseExpr() orelse error.ExpectedExpr;
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

fn addNode(p: *Parse, elem: Tree.Node) Allocator.Error!Node.Index {
    const res: Node.Index = @enumFromInt(p.nodes.len);
    try p.nodes.append(p.allocator, elem);
    return res;
}

fn nextToken(p: *Parse) TokenIndex {
    const res = p.tok_i;
    p.tok_i += 1;
    return res;
}
