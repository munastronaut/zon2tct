const std = @import("std");
const Allocator = std.mem.Allocator;

const Tree = @import("Tree.zig");
const TokenIndex = Tree.TokenIndex;

allocator: Allocator,
src: []const u8,
toks: Tree.TokenList.Slice,
tok_i: TokenIndex,
nodes: Tree.NodeList,
extra_data: std.ArrayList(u32),
