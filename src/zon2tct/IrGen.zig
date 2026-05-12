const IrGen = @This();

const Ir = @import("Ir.zig");
const Tree = @import("Tree.zig");

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;
const hash_map = std.hash_map;
const StringIndexAdapter = hash_map.StringIndexAdapter;
const StringIndexContext = hash_map.StringIndexContext;

gpa: Allocator,
tree: Tree,

extra: std.ArrayList(u32),
string_bytes: std.ArrayList(u8),
string_table: std.HashMapUnmanaged(u32, void, StringIndexContext, hash_map.default_max_load_percentage),

candidates: SymbolTable,
states: SymbolTable,
issues: SymbolTable,

compile_errors: std.ArrayList(Ir.CompileError),
error_notes: std.ArrayList(Ir.CompileError.Note),

const SymbolTable = std.HashMapUnmanaged(u32, u32, StringIndexContext, hash_map.default_max_load_percentage);

pub const testing: IrGen = .{
    .gpa = std.testing.allocator,
    .tree = undefined,
    .extra = .empty,
    .string_bytes = .empty,
    .string_table = .empty,
    .candidates = .empty,
    .states = .empty,
    .issues = .empty,
    .compile_errors = .empty,
    .error_notes = .empty,
};

pub fn generate(gpa: Allocator, tree: Tree) Allocator.Error!Ir {
    var ig: IrGen = .{
        .gpa = gpa,
        .tree = tree,
        .extra = .empty,
        .string_bytes = .empty,
        .string_table = .empty,
        .candidates = .empty,
        .states = .empty,
        .issues = .empty,
        .compile_errors = .empty,
        .error_notes = .empty,
    };
    defer ig.deinit();

    var payload: Ir.Payload = .{
        .questions = .empty,
        .answers = .empty,
        .global_effects = .empty,
        .state_effects = .empty,
        .issue_effects = .empty,
    };
    errdefer payload.deinit(gpa);

    const root = try ig.parseRoot();
    if (root.definitions) |def_node| {
        try ig.lowerDefinitions(def_node);
    }

    const player_cand = if (root.player_cand) |pc_node|
        try ig.resolveCandidate(pc_node)
    else
        null;

    if (root.questions) |qn_node| {
        _ = qn_node;
    } else {
        // error - no questions
    }

    return .{
        .string_bytes = ig.string_bytes.toOwnedSlice(gpa),
        .player = if (player_cand) |pk| .{ .pk = pk } else .default,
        .payload = payload,
    };
}

fn deinit(ig: *IrGen) void {
    ig.extra.deinit(ig.gpa);
    ig.string_bytes.deinit(ig.gpa);
    ig.string_table.deinit(ig.gpa);
    ig.candidates.deinit(ig.gpa);
    ig.states.deinit(ig.gpa);
    ig.issues.deinit(ig.gpa);
    ig.compile_errors.deinit(ig.gpa);
    ig.error_notes.deinit(ig.gpa);
}

fn internString(ig: *IrGen, slice: []const u8) Allocator.Error!u32 {
    const gpa = ig.gpa;
    const string_bytes = &ig.string_bytes;

    const gop = try ig.string_table.getOrPutContextAdapted(
        gpa,
        slice,
        StringIndexAdapter{ .bytes = string_bytes },
        StringIndexContext{ .bytes = string_bytes },
    );
    if (gop.found_existing) return gop.key_ptr.*;

    const str_idx: u32 = @intCast(string_bytes.items.len);
    try string_bytes.appendSlice(gpa, slice);
    try string_bytes.append(gpa, 0);

    gop.key_ptr.* = str_idx;
    return str_idx;
}

test "string interning - deduplication" {
    var ig: IrGen = .testing;
    defer ig.deinit();
    const idx = try ig.internString("foo");
    try std.testing.expect(idx == try ig.internString("foo"));
}

test "string interning - indexing" {
    var ig: IrGen = .testing;
    defer ig.deinit();
    _ = try ig.internString("foo");
    _ = try ig.internString("bar");
    const idx = try ig.internString("baz");
    try std.testing.expect(idx == 8);
}

const Root = struct {
    definitions: ?Tree.Node.Index = null,
    player_cand: ?Tree.Node.Index = null,
    questions: ?Tree.Node.Index = null,
};

fn parseRoot(ig: *IrGen) !Root {
    var result: Root = .{};
    const root_node = ig.tree.nodeData(.root).node;

    var buf: [2]Tree.Node.Index = undefined;
    const full = ig.tree.fullStructInit(&buf, root_node) orelse {
        // emit an error here
        return result;
    };

    for (full.tree.fields) |val_node| {
        const ident_tok = getFieldIdentTok(ig.tree, val_node);
        const name = ig.tree.tokenSlice(ident_tok);

        if (mem.eql(u8, name, "definitions")) {
            if (result.definitions) |_| {} // duplicate field error
            result.definitions = val_node;
        } else if (mem.eql(u8, name, "player_candidate")) {
            if (result.player_cand) |_| {} // duplicate field error
            result.player_cand = val_node;
        } else if (mem.eql(u8, name, "questions")) {
            if (result.questions) |_| {} // duplicate field error
            result.questions = val_node;
        } else {
            // error/warning about unknown field
        }
    }

    return result;
}

fn getFieldIdentTok(tree: Tree, val_node: Tree.Node.Index) Tree.TokenIndex {
    const main_tok = tree.nodeMainToken(val_node);
    const ident_tok = main_tok - 2;
    assert(tree.tokenId(ident_tok) == .identifier);
    return ident_tok;
}

fn getFieldName(tree: Tree, val_node: Tree.Node.Index) []const u8 {
    return tree.tokenSlice(getFieldIdentTok(tree, val_node));
}

fn lowerDefinitions(ig: *IrGen, def_node: Tree.Node.Index) !void {
    _ = ig;
    _ = def_node;
}

fn resolveCandidate(ig: *IrGen, pc_node: Tree.Node.Index) Allocator.Error!u32 {
    const id = ig.tree.nodeId(pc_node);
    const slice = ig.tree.tokenSlice(ig.tree.nodeMainToken(pc_node));

    switch (id) {
        .number_literal => return std.fmt.parseInt(u32, slice, 10) catch |e| {
            // emit error here
            switch (e) {
                error.Overflow => {},
                error.InvalidCharacter => {},
            }
            return 0;
        },
        .enum_literal => {
            const idx = try ig.internString(slice);
            if (ig.candidates.getAdapted(
                idx,
                StringIndexContext{ .bytes = &ig.string_bytes },
            )) |val| {
                return val;
            } else {
                // emit error here
                return 0;
            }
        },
        else => {},
    }
}

fn errNoteNode(
    ig: *IrGen,
    node: Tree.Node.Index,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!Ir.CompileError.Note {
    const msg_idx: u32 = @intCast(ig.string_bytes.items.len);
    try ig.string_bytes.print(ig.gpa, fmt ++ "\x00", args);
    return .{
        .msg = @enumFromInt(msg_idx),
        .token = .none,
        .node_or_offset = @intFromEnum(node),
    };
}

fn errNoteTok(
    ig: *IrGen,
    tok: Tree.TokenIndex,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!Ir.CompileError.Note {
    const msg_idx: u32 = @intCast(ig.string_bytes.items.len);
    try ig.string_bytes.print(ig.gpa, fmt ++ "\x00", args);
    return .{
        .msg = @enumFromInt(msg_idx),
        .token = .fromToken(tok),
        .node_or_offset = 0,
    };
}

fn addErrorTokNotes(
    ig: *IrGen,
    tok: Tree.TokenIndex,
    comptime fmt: []const u8,
    args: anytype,
    notes: []const Ir.CompileError.Note,
) Allocator.Error!void {
    return ig.addErrorInner(.fromToken(tok), 0, fmt, args, notes);
}

fn addErrorInner(
    ig: *IrGen,
    token: Tree.OptionalTokenIndex,
    node_or_offset: u32,
    comptime fmt: []const u8,
    args: anytype,
    notes: []const Ir.CompileError.Note,
) Allocator.Error!void {
    const gpa = ig.gpa;

    const first_note: u32 = @intCast(ig.error_notes.items.len);
    try ig.error_notes.appendSlice(gpa, notes);

    const msg_idx: u32 = @intCast(ig.string_bytes.items.len);
    try ig.string_bytes.print(gpa, fmt ++ "\x00", args);

    try ig.compile_errors.append(gpa, .{
        .msg = @enumFromInt(msg_idx),
        .token = token,
        .node_or_offset = node_or_offset,
        .first_note = first_note,
        .note_count = @intCast(notes.len),
    });
}
