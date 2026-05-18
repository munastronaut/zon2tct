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
const Writer = std.Io.Writer;

gpa: Allocator,
tree: Tree,

string_bytes: std.ArrayList(u8),
string_table: std.HashMapUnmanaged(u32, void, StringIndexContext, hash_map.default_max_load_percentage),

candidates: SymbolTable,
states: SymbolTable,
issues: SymbolTable,

compile_errors: std.ArrayList(Ir.CompileError),
error_notes: std.ArrayList(Ir.CompileError.Note),

const SymbolTable = std.HashMapUnmanaged(u32, u32, StringIndexContext, hash_map.default_max_load_percentage);

pub fn generate(gpa: Allocator, tree: Tree) Allocator.Error!Ir {
    var ig: IrGen = .{
        .gpa = gpa,
        .tree = tree,
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

    const player_cand = if (root.player_candidate) |pc_node|
        try ig.resolvePk(pc_node)
    else
        null;

    if (root.questions) |qn_node| {
        _ = qn_node;
    } else {
        // error - no questions
    }

    if (ig.compile_errors.items.len > 0) {
        const string_bytes = try ig.string_bytes.toOwnedSlice(gpa);
        errdefer gpa.free(string_bytes);
        const compile_errors = try ig.compile_errors.toOwnedSlice(gpa);
        errdefer gpa.free(compile_errors);
        const error_notes = try ig.error_notes.toOwnedSlice(gpa);
        errdefer gpa.free(error_notes);

        return .{
            .string_bytes = string_bytes,
            .player = if (player_cand) |pk| .{ .pk = pk } else .default,
            .payload = payload,
            .compile_errors = compile_errors,
            .error_notes = error_notes,
        };
    } else {
        assert(ig.error_notes.items.len == 0);

        const string_bytes = try ig.string_bytes.toOwnedSlice(gpa);
        errdefer gpa.free(string_bytes);

        return .{
            .string_bytes = string_bytes,
            .player = if (player_cand) |pk| .{ .pk = pk } else .default,
            .payload = payload,
            .compile_errors = &.{},
            .error_notes = &.{},
        };
    }
}

fn deinit(ig: *IrGen) void {
    ig.string_bytes.deinit(ig.gpa);
    ig.string_table.deinit(ig.gpa);
    ig.candidates.deinit(ig.gpa);
    ig.states.deinit(ig.gpa);
    ig.issues.deinit(ig.gpa);
    ig.compile_errors.deinit(ig.gpa);
    ig.error_notes.deinit(ig.gpa);
}

fn appendIdentStr(ig: *IrGen, ident_tok: Tree.TokenIndex) (Allocator.Error || error{BadString})!u32 {
    const gpa = ig.gpa;
    const tree = ig.tree;
    assert(tree.tokenId(ident_tok) == .identifier);
    const ident_name = tree.tokenSlice(ident_tok);
    if (!mem.startsWith(u8, ident_name, "@")) {
        const start = ig.string_bytes.items.len;
        try ig.string_bytes.appendSlice(gpa, ident_name);
        return @intCast(start);
    }
    const offset = 1;
    const start: u32 = @intCast(ig.string_bytes.items.len);
    const raw_str = ig.tree.tokenSlice(ident_tok)[offset..];
    try ig.string_bytes.ensureUnusedCapacity(gpa, raw_str.len);
    const result = result: {
        var aw: Writer.Allocating = .fromArrayList(gpa, &ig.string_bytes);
        defer ig.string_bytes = aw.toArrayList();
        break :result std.zig.string_literal.parseWrite(&aw.writer, raw_str) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
    };
    switch (result) {
        .success => {},
        .failure => |err| {
            try ig.lowerStrLitError(err, ident_tok, raw_str, offset);
            return error.BadString;
        },
    }

    const slice = ig.string_bytes.items[start..];
    if (mem.findScalar(u8, slice, 0)) |_| {
        try ig.addErrorTok(ident_tok, "identifier cannot have null bytes", .{});
        return error.BadString;
    } else if (slice.len == 0) {
        try ig.addErrorTok(ident_tok, "identifier cannot be empty", .{});
        return error.BadString;
    }
    return start;
}

fn identAsString(ig: *IrGen, ident_tok: Tree.TokenIndex) (Allocator.Error || error{BadString})!Ir.NullTerminatedString {
    const gpa = ig.gpa;
    const string_bytes = &ig.string_bytes;
    const str_idx = try ig.appendIdentStr(ident_tok);
    const key: []const u8 = string_bytes.items[str_idx..];
    const gop = try ig.string_table.getOrPutContextAdapted(
        gpa,
        key,
        StringIndexAdapter{ .bytes = string_bytes },
        StringIndexContext{ .bytes = string_bytes },
    );
    if (gop.found_existing) {
        string_bytes.shrinkRetainingCapacity(str_idx);
        return @enumFromInt(gop.key_ptr.*);
    }
    gop.key_ptr.* = str_idx;
    try string_bytes.append(gpa, 0);
    return @enumFromInt(str_idx);
}

fn lowerStrLitError(
    ig: *IrGen,
    err: std.zig.string_literal.Error,
    tok: Tree.TokenIndex,
    raw_str: []const u8,
    offset: u32,
) Allocator.Error!void {
    return ig.addErrorTokOff(tok, @intCast(offset + err.offset()), "{f}", .{err.fmt(raw_str)});
}

const Root = struct {
    definitions: ?Tree.Node.Index = null,
    player_candidate: ?Tree.Node.Index = null,
    questions: ?Tree.Node.Index = null,
};

fn parseRoot(ig: *IrGen) Allocator.Error!Root {
    var result: Root = .{};
    const root_node = ig.tree.nodeData(.root).node;

    var buf: [2]Tree.Node.Index = undefined;
    const full = ig.tree.fullStructInit(&buf, root_node).?;

    for (full.tree.fields) |val_node| {
        const ident_tok = ig.tree.firstToken(val_node) - 2;

        if (ig.identAsString(ident_tok)) |name_str| {
            const raw_str = raw_str: {
                const idx = mem.findScalar(u8, ig.string_bytes.items[@intFromEnum(name_str)..], 0).?;
                break :raw_str ig.string_bytes.items[@intFromEnum(name_str)..][0..idx :0];
            };
            if (std.meta.stringToEnum(std.meta.FieldEnum(Root), raw_str)) |field_enum| {
                switch (field_enum) {
                    inline else => |tag| {
                        const field_name = @tagName(tag);
                        if (@field(result, field_name)) |prev_node| {
                            const prev_tok = ig.tree.firstToken(prev_node) - 2;
                            try ig.addErrorTokNotes(ident_tok, "duplicate struct field name", .{}, &.{
                                try ig.errNoteTok(prev_tok, "duplicate name here", .{}),
                            });
                        } else {
                            @field(result, field_name) = val_node;
                        }
                    },
                }
            } else {
                try ig.addErrorTok(ident_tok, "unknown field '{s}'", .{raw_str});
            }
        } else |err| switch (err) {
            error.BadString => {},
            error.OutOfMemory => |e| return e,
        }
    }

    return result;
}

test parseRoot {
    const test_str =
        \\.{
        \\    .definitions = .{ .candidates = .{} },
        \\    .player_candidate = 50,
        \\    .questions = .{},
        \\}
    ;

    var tree: Tree = try .parse(std.testing.allocator, test_str);
    defer tree.deinit(std.testing.allocator);
    var ig: IrGen = .{
        .gpa = std.testing.allocator,
        .tree = tree,
        .string_bytes = .empty,
        .string_table = .empty,
        .candidates = .empty,
        .states = .empty,
        .issues = .empty,
        .compile_errors = .empty,
        .error_notes = .empty,
    };
    defer ig.deinit();
    const root = try ig.parseRoot();
    inline for (std.meta.fields(Root)) |field| {
        try std.testing.expect(@field(root, field.name) != null);
    }
}

fn lowerDefinitions(ig: *IrGen, def_node: Tree.Node.Index) !void {
    _ = ig;
    _ = def_node;
}

fn resolvePk(ig: *IrGen, pk_node: Tree.Node.Index) Allocator.Error!u32 {
    const tree = ig.tree;
    const id = tree.nodeId(pk_node);
    const tok = tree.nodeMainToken(pk_node);
    const slice = tree.tokenSlice(tok);

    switch (id) {
        .number_literal => if (std.fmt.parseInt(u32, slice, 10)) |pk| return pk else |err| switch (err) {
            error.Overflow => try ig.addErrorTok(tok, "pk overflows u32 range", .{}),
            error.InvalidCharacter => try ig.addErrorTok(tok, "invalid character in pk", .{}),
        },
        .enum_literal => {
            const idx = ig.identAsString(tok) catch |err| switch (err) {
                error.BadString => undefined,
                error.OutOfMemory => |e| return e,
            };
            if (ig.candidates.getAdapted(@intFromEnum(idx), StringIndexContext{ .bytes = &ig.string_bytes })) |val| {
                return val;
            } else {
                try ig.addErrorTok(tok, "could not resolve pk from alias '{s}'", .{slice});
            }
        },
        .negation => {
            const child_node = tree.nodeData(pk_node).node;
            switch (tree.nodeId(child_node)) {
                .number_literal => try ig.addErrorTok(tok, "pk underflows u32 range", .{}),
                .identifier => {
                    const child_ident = tree.tokenSlice(tree.nodeMainToken(child_node));
                    if (mem.eql(u8, child_ident, "inf"))
                        try ig.addErrorTok(tok, "'inf' can be only represented by floats; cannot be used for negation with u32", .{});
                },
                else => {},
            }
            try ig.addErrorTok(tok, "expected integer after '-'", .{});
        },
        else => try ig.addErrorTok(tok, "expected enum literal or integer", .{}),
    }
    return 0;
}

test resolvePk {
    try testResolvePk(
        \\.{
        \\    .player_candidate = 100,
        \\}
    , 100);
    try testResolvePk(
        \\.{
        \\    .player_candidate = 4_294_967_295,
        \\}
    , std.math.maxInt(u32));
    try testResolvePkExpectErr(
        \\.{
        \\    .player_candidate = 281_474_976_710_655,
        \\}
    , "pk overflows u32 range");
    try testResolvePkExpectErr(
        \\.{
        \\    .player_candidate = -100,
        \\}
    , "expected integer after '-'");
    try testResolvePkExpectErr(
        \\.{
        \\    .player_candidate = hello,
        \\}
    , "expected enum literal or integer");
    try testResolvePkExpectErr(
        \\.{
        \\    .player_candidate = .foo,
        \\}
    , "could not resolve pk from alias 'foo'");
}

fn testResolvePk(src: [:0]const u8, expected: u32) !void {
    const gpa = std.testing.allocator;
    var tree: Tree = try .parse(gpa, src);
    defer tree.deinit(gpa);
    var ig: IrGen = .{
        .gpa = gpa,
        .tree = tree,
        .string_bytes = .empty,
        .string_table = .empty,
        .candidates = .empty,
        .states = .empty,
        .issues = .empty,
        .compile_errors = .empty,
        .error_notes = .empty,
    };
    defer ig.deinit();
    const root = try ig.parseRoot();

    const player_cand = if (root.player_candidate) |pc_node|
        try ig.resolvePk(pc_node)
    else
        null;

    return std.testing.expectEqual(expected, player_cand);
}

fn testResolvePkExpectErr(src: [:0]const u8, err_str: []const u8) !void {
    const gpa = std.testing.allocator;
    var tree: Tree = try .parse(gpa, src);
    defer tree.deinit(gpa);
    var ig: IrGen = .{
        .gpa = gpa,
        .tree = tree,
        .string_bytes = .empty,
        .string_table = .empty,
        .candidates = .empty,
        .states = .empty,
        .issues = .empty,
        .compile_errors = .empty,
        .error_notes = .empty,
    };
    defer ig.deinit();
    const root = try ig.parseRoot();

    const player_cand = if (root.player_candidate) |pc_node|
        try ig.resolvePk(pc_node)
    else
        null;

    try std.testing.expectEqual(0, player_cand);
    var iter = mem.splitBackwardsScalar(u8, ig.string_bytes.items, 0);
    _ = iter.next();
    const raw_msg = iter.next().?;
    try std.testing.expectEqualStrings(err_str, raw_msg);
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

fn addErrorNode(
    ig: *IrGen,
    node: Tree.Node.Index,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!void {
    return ig.addErrorInner(.none, @intFromEnum(node), fmt, args, &.{});
}

fn addErrorTok(
    ig: *IrGen,
    tok: Tree.TokenIndex,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!void {
    return ig.addErrorInner(.fromToken(tok), 0, fmt, args, &.{});
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

fn addErrorNodeNotes(
    ig: *IrGen,
    node: Tree.Node.Index,
    comptime fmt: []const u8,
    args: anytype,
    notes: []const Ir.CompileError.Note,
) Allocator.Error!void {
    return ig.addErrorInner(.none, @intFromEnum(node), fmt, args, notes);
}

fn addErrorTokOff(
    ig: *IrGen,
    tok: Tree.TokenIndex,
    offset: u32,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!void {
    return ig.addErrorInner(.fromToken(tok), offset, fmt, args, &.{});
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
