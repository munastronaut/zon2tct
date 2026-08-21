const Parse = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zon2tct = @import("../zon2tct.zig");
const Tree = zon2tct.Tree;
const Node = Tree.Node;
const Token = zon2tct.Token;
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

fn warn(p: *Parse, id: Tree.Error.Id) Error!void {
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
        .expected_prefix_expr,
        .expected_comma_after_initializer,
        .expected_token,
        => if (msg.token != 0 and p.tokensOnSameLine(msg.token - 1, msg.token)) {
            var copy = msg;
            copy.token_is_prev = true;
            copy.token -= 1;
            return p.errors.append(p.gpa, copy);
        },
        else => {},
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
        .minus => return try p.addNode(.{
            .id = .negation,
            .main_tok = p.nextToken(),
            .data = .{ .node = try p.expectValue() },
        }),
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
            while (p.tokenId(p.tok_i) == .multiline_string_literal_line) {
                p.tok_i += 1;
            }
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

                const scratch_top = p.scratch.items.len;
                defer p.scratch.shrinkRetainingCapacity(scratch_top);
                const opt_field_init = try p.parseFieldInit();
                if (opt_field_init) |field_init| {
                    try p.scratch.append(p.gpa, field_init);
                    while (true) {
                        switch (p.tokenId(p.tok_i)) {
                            .comma => p.tok_i += 1,
                            .r_brace => {
                                p.tok_i += 1;
                                break;
                            },
                            .r_paren => return p.failExpected(.r_brace),
                            else => try p.warn(.expected_comma_after_initializer),
                        }
                        if (p.eatToken(.r_brace)) |_| break;
                        const next = try p.expectFieldInit();
                        try p.scratch.append(p.gpa, next);
                    }
                    const comma = p.tokenId(p.tok_i - 2) == .comma;
                    const inits = p.scratch.items[scratch_top..];
                    std.debug.assert(inits.len != 0);
                    if (inits.len <= 2) {
                        return try p.addNode(.{
                            .id = if (comma) .struct_init_dot_two_comma else .struct_init_dot_two,
                            .main_tok = l_brace,
                            .data = .{
                                .opt_node_and_opt_node = .{
                                    if (inits.len >= 1) .fromOptional(inits[0]) else .none,
                                    if (inits.len >= 2) .fromOptional(inits[1]) else .none,
                                },
                            },
                        });
                    } else {
                        return try p.addNode(.{
                            .id = if (comma) .struct_init_dot_comma else .struct_init_dot,
                            .main_tok = l_brace,
                            .data = .{ .extra_range = try p.listToSpan(inits) },
                        });
                    }
                }

                while (true) {
                    if (p.eatToken(.r_brace)) |_| break;
                    const elem_init = try p.expectValue();
                    try p.scratch.append(p.gpa, elem_init);
                    switch (p.tokenId(p.tok_i)) {
                        .comma => p.tok_i += 1,
                        .r_brace => {
                            p.tok_i += 1;
                            break;
                        },
                        .r_paren => return p.failExpected(.r_brace),
                        else => try p.warn(.expected_comma_after_initializer),
                    }
                }
                const comma = p.tokenId(p.tok_i - 2) == .comma;
                const inits = p.scratch.items[scratch_top..];
                if (inits.len <= 2) {
                    return try p.addNode(.{
                        .id = if (inits.len == 0) .struct_init_dot_two else if (comma) .array_init_dot_two_comma else .array_init_dot_two,
                        .main_tok = l_brace,
                        .data = .{
                            .opt_node_and_opt_node = .{
                                if (inits.len >= 1) inits[0].toOptional() else .none,
                                if (inits.len >= 2) inits[1].toOptional() else .none,
                            },
                        },
                    });
                } else {
                    return try p.addNode(.{
                        .id = if (comma) .array_init_dot_comma else .array_init_dot,
                        .main_tok = l_brace,
                        .data = .{ .extra_range = try p.listToSpan(inits) },
                    });
                }
            },
            else => return null,
        },
        else => return null,
    }
}

fn expectValue(p: *Parse) Error!Node.Index {
    return try p.parseValue() orelse p.fail(.expected_expr);
}

fn parseFieldInit(p: *Parse) Error!?Node.Index {
    if (p.eatTokens(&.{ .period, .identifier, .equal })) |_| {
        return try p.expectValue();
    }
    return null;
}

fn expectFieldInit(p: *Parse) Error!Node.Index {
    if (p.eatTokens(&.{ .period, .identifier, .equal })) |_| {
        return try p.expectValue();
    }
    return p.fail(.expected_initializer);
}

fn listToSpan(p: *Parse, list: []const Node.Index) Allocator.Error!Node.SubRange {
    try p.extra_data.appendSlice(p.gpa, @ptrCast(list));
    return .{
        .start = @fromBackingInt(@intCast(p.extra_data.items.len - list.len)),
        .end = @fromBackingInt(@intCast(p.extra_data.items.len)),
    };
}

fn addNode(p: *Parse, elem: Tree.Node) Allocator.Error!Node.Index {
    const res: Node.Index = @fromBackingInt(@intCast(p.nodes.len));
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
