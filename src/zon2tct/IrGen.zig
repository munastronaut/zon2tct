const IrGen = @This();

const zon2tct = @import("zon2tct.zig");
const Ir = zon2tct.Ir;
const Tree = zon2tct.Tree;

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

player: ?u32,
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
        .player = null,
        .candidates = .empty,
        .states = .empty,
        .issues = .empty,
        .compile_errors = .empty,
        .error_notes = .empty,
    };
    defer ig.deinit();

    try ig.string_bytes.append(gpa, 0);

    var wip: Ir.Payload.Wip = .{
        .symbols = .empty,
        .questions = .empty,
        .answers = .empty,
        .feedbacks = .empty,
        .global_effects = .empty,
        .state_effects = .empty,
        .issue_effects = .empty,
    };
    errdefer wip.deinit(gpa);

    if (tree.errors.len == 0) {
        const root_node = tree.nodeData(.root).node;
        const root = try ig.parseStruct(Root, root_node);

        if (root.definitions) |def_node| {
            try ig.lowerDefinitions(def_node);
        }

        if (root.player_candidate) |pc_node| {
            ig.player = try ig.resolvePk(pc_node, &ig.candidates);
        }

        if (root.questions) |qn_node| {
            try ig.lowerQuestions(&wip, qn_node);
        } else {
            try ig.addErrorNode(root_node, "root node must have 'questions' field", .{});
        }
    } else {
        try ig.lowerAstErrors();
    }

    if (ig.compile_errors.items.len > 0) {
        const string_bytes = try ig.string_bytes.toOwnedSlice(gpa);
        errdefer gpa.free(string_bytes);
        var payload = try wip.toOwnedPayload(gpa);
        errdefer payload.deinit(gpa);
        const compile_errors = try ig.compile_errors.toOwnedSlice(gpa);
        errdefer gpa.free(compile_errors);
        const error_notes = try ig.error_notes.toOwnedSlice(gpa);
        errdefer gpa.free(error_notes);

        return .{
            .string_bytes = string_bytes,
            .player = if (ig.player) |pk| .{ .pk = pk } else .default,
            .payload = payload,
            .compile_errors = compile_errors,
            .error_notes = error_notes,
        };
    } else {
        assert(ig.error_notes.items.len == 0);

        const string_bytes = try ig.string_bytes.toOwnedSlice(gpa);
        errdefer gpa.free(string_bytes);
        var payload = try wip.toOwnedPayload(gpa);
        errdefer payload.deinit(gpa);

        return .{
            .string_bytes = string_bytes,
            .player = if (ig.player) |pk| .{ .pk = pk } else .default,
            .payload = payload,
            .compile_errors = &.{},
            .error_notes = &.{},
        };
    }
}

test generate {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    const path = "examples/1960.zon";
    var f = std.Io.Dir.cwd().openFile(io, path, .{}) catch unreachable;

    var read_buf: [1024]u8 = undefined;
    var file_reader = f.reader(io, &read_buf);
    const src = try zon2tct.readSourceFileToEndAlloc(gpa, &file_reader);
    defer gpa.free(src);

    var tree: Tree = try .parse(gpa, src);
    defer tree.deinit(gpa);

    var ir = try generate(gpa, tree);
    defer ir.deinit(gpa);

    if (ir.hasCompileErrors()) {
        var wip: zon2tct.ErrorBundle.Wip = undefined;
        try wip.init(gpa);
        defer wip.deinit();
        try wip.addIrErrorMessages(ir, tree, src, path);
        var eb = try wip.toOwnedBundle();
        defer eb.deinit(gpa);
        eb.renderToStderr(io, .auto) catch {};
    }

    try std.testing.expect(!ir.hasCompileErrors());
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
    const raw_str = tree.tokenSlice(ident_tok)[offset..];
    try ig.string_bytes.ensureUnusedCapacity(gpa, raw_str.len);
    const result = r: {
        var aw: Writer.Allocating = .fromArrayList(gpa, &ig.string_bytes);
        defer ig.string_bytes = aw.toArrayList();
        break :r std.zig.string_literal.parseWrite(&aw.writer, raw_str) catch |err| switch (err) {
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
        try ig.addErrorTok(ident_tok, "identifier cannot contain null bytes", .{});
        return error.BadString;
    } else if (slice.len == 0) {
        try ig.addErrorTok(ident_tok, "identifier cannot be empty", .{});
        return error.BadString;
    }
    return start;
}

pub fn strLitSizeHint(tree: Tree, node: Tree.Node.Index) usize {
    switch (tree.nodeId(node)) {
        .string_literal => {
            const tok = tree.nodeMainToken(node);
            const raw_str = tree.tokenSlice(tok);
            return raw_str.len;
        },
        .multiline_string_literal => {
            const first_tok, const last_tok = tree.nodeData(node).token_and_token;

            var size = tree.tokenSlice(first_tok)[2..].len;
            for (first_tok + 1..last_tok + 1) |tok_idx| {
                size += 1;
                size += tree.tokenSlice(@intCast(tok_idx))[2..].len;
            }
            return size;
        },
        else => unreachable,
    }
}

pub fn parseStrLit(
    tree: Tree,
    node: Tree.Node.Index,
    writer: *Writer,
) Writer.Error!std.zig.string_literal.Result {
    switch (tree.nodeId(node)) {
        .string_literal => {
            const tok = tree.nodeMainToken(node);
            const raw_str = tree.tokenSlice(tok);
            return std.zig.string_literal.parseWrite(writer, raw_str);
        },
        .multiline_string_literal => {
            const first_tok, const last_tok = tree.nodeData(node).token_and_token;

            {
                const line_bytes = tree.tokenSlice(first_tok)[2..];
                try writer.writeAll(line_bytes);
            }

            for (first_tok + 1..last_tok + 1) |tok_idx| {
                const line_bytes = tree.tokenSlice(@intCast(tok_idx))[2..];
                try writer.writeByte('\n');
                try writer.writeAll(line_bytes);
            }

            return .success;
        },
        else => unreachable,
    }
}

const StringLiteralResult = union(enum) {
    nts: Ir.NullTerminatedString,
    slice: Slice,

    pub const Slice = struct { start: u32, len: u32 };
};

fn strLitAsString(ig: *IrGen, str_node: Tree.Node.Index) (Allocator.Error || error{BadString})!StringLiteralResult {
    const gpa = ig.gpa;
    const string_bytes = &ig.string_bytes;
    const str_idx: u32 = @intCast(ig.string_bytes.items.len);
    const size_hint = strLitSizeHint(ig.tree, str_node);
    try string_bytes.ensureUnusedCapacity(gpa, size_hint);
    const result = r: {
        var aw: Writer.Allocating = .fromArrayList(gpa, &ig.string_bytes);
        defer ig.string_bytes = aw.toArrayList();
        break :r parseStrLit(ig.tree, str_node, &aw.writer) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
    };
    switch (result) {
        .success => {},
        .failure => |err| {
            const tok = ig.tree.nodeMainToken(str_node);
            const raw_str = ig.tree.tokenSlice(tok);
            try ig.lowerStrLitError(err, tok, raw_str, 0);
            return error.BadString;
        },
    }
    const key: []const u8 = string_bytes.items[str_idx..];
    if (mem.findScalar(u8, key, 0)) |_| return .{
        .slice = .{
            .start = str_idx,
            .len = @intCast(key.len),
        },
    };
    const gop = try ig.string_table.getOrPutContextAdapted(
        gpa,
        key,
        StringIndexAdapter{ .bytes = string_bytes },
        StringIndexContext{ .bytes = string_bytes },
    );
    if (gop.found_existing) {
        string_bytes.shrinkRetainingCapacity(str_idx);
        return .{ .nts = @fromBackingInt(gop.key_ptr.*) };
    }
    gop.key_ptr.* = str_idx;
    try string_bytes.append(gpa, 0);
    return .{ .nts = @fromBackingInt(gop.key_ptr.*) };
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
        return @fromBackingInt(gop.key_ptr.*);
    }
    gop.key_ptr.* = str_idx;
    try string_bytes.append(gpa, 0);
    return @fromBackingInt(str_idx);
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

fn parseStruct(ig: *IrGen, comptime T: type, node: Tree.Node.Index) Allocator.Error!T {
    assert(@typeInfo(T) == .@"struct");
    var result: T = .{};

    var buf: [2]Tree.Node.Index = undefined;
    const full = ig.tree.fullStructInit(&buf, node).?;

    const FieldEnum = std.meta.FieldEnum(T);
    const field_info = @typeInfo(FieldEnum).@"enum";

    for (full.tree.fields) |val_node| {
        const ident_tok = ig.tree.firstToken(val_node) - 2;

        if (ig.identAsString(ident_tok)) |name_str| {
            const raw_str = name_str.getAny(ig.string_bytes.items);
            if (std.meta.stringToEnum(FieldEnum, raw_str)) |field_enum| {
                inline for (field_info.field_names) |enum_field_name| {
                    if (field_enum == @field(FieldEnum, enum_field_name)) {
                        const field_name = enum_field_name;
                        if (@field(result, field_name)) |prev_node| {
                            const prev_tok = ig.tree.firstToken(prev_node) - 2;
                            try ig.addErrorTokNotes(ident_tok, "duplicate struct field name", .{}, &.{
                                try ig.errNoteTok(prev_tok, "duplicate name here", .{}),
                            });
                        } else {
                            @field(result, field_name) = val_node;
                        }
                    }
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

fn lowerDefinitions(ig: *IrGen, def_node: Tree.Node.Index) Allocator.Error!void {
    const tree = ig.tree;
    const definitions = try ig.parseStruct(Definitions, def_node);

    const info = @typeInfo(Definitions).@"struct";
    const field_names = info.field_names;

    inline for (field_names) |field_name| {
        if (@field(definitions, field_name)) |node| {
            var buf: [2]Tree.Node.Index = undefined;
            const full = tree.fullStructInit(&buf, node).?;

            const table: *SymbolTable = &@field(ig, field_name);

            for (full.tree.fields) |val_node| {
                const ident_tok = tree.firstToken(val_node) - 2;

                if (tree.tokenId(ident_tok) != .identifier) {
                    try ig.addErrorNode(val_node, "expected key-value pair for definition", .{});
                    continue;
                }

                if (ig.identAsString(ident_tok)) |name_str| {
                    const value = try ig.resolvePk(val_node, table) orelse continue;
                    const gop = try table.getOrPutContext(ig.gpa, @backingInt(name_str), StringIndexContext{ .bytes = &ig.string_bytes });
                    if (gop.found_existing) {
                        const raw_str = name_str.getAny(ig.string_bytes.items);
                        try ig.addErrorTok(ident_tok, "duplicate definition for '{s}'", .{raw_str});
                    } else {
                        gop.value_ptr.* = value;
                    }
                } else |err| switch (err) {
                    error.BadString => {},
                    error.OutOfMemory => |e| return e,
                }
            }
        }
    }
}

fn resolvePk(ig: *IrGen, pk_node: Tree.Node.Index, table: *const SymbolTable) Allocator.Error!?u32 {
    const tree = ig.tree;
    const id = tree.nodeId(pk_node);
    const tok = tree.nodeMainToken(pk_node);
    const slice = tree.tokenSlice(tok);

    switch (id) {
        .number_literal => if (std.fmt.parseInt(u32, slice, 10)) |pk| return pk else |err| switch (err) {
            error.Overflow => try ig.addErrorTok(tok, "pk overflows u32 range", .{}),
            error.InvalidCharacter => try ig.addErrorTok(tok, "invalid character in integer pk", .{}),
        },
        .enum_literal => if (ig.identAsString(tok)) |idx| {
            if (table.getAdapted(@backingInt(idx), StringIndexContext{ .bytes = &ig.string_bytes })) |val| {
                return val;
            } else {
                const ident = idx.getAny(ig.string_bytes.items);
                const suggestion = ig.suggest(ident, table);
                if (suggestion != .empty) {
                    const str = suggestion.getAny(ig.string_bytes.items);
                    try ig.addErrorTokNotes(tok, "undefined alias '{s}'", .{ident}, &.{
                        try ig.errNoteTok(tok, "did you mean '{s}'?", .{str}),
                    });
                } else {
                    try ig.addErrorTok(tok, "undefined alias '{s}'", .{ident});
                }
            }
        } else |err| switch (err) {
            error.BadString => {},
            error.OutOfMemory => |e| return e,
        },
        .negation => {
            const child_node = tree.nodeData(pk_node).node;
            const child_slice = tree.tokenSlice(tree.nodeMainToken(child_node));
            switch (tree.nodeId(child_node)) {
                .number_literal => {
                    if (std.fmt.parseInt(u32, child_slice, 10)) |pk| {
                        if (pk == 0) {
                            try ig.addErrorTokNotes(tok, "integer literal '-0' is ambiguous", .{}, &.{
                                try ig.errNoteTok(tok, "use '0' for an integer zero", .{}),
                                try ig.errNoteTok(tok, "use '-0.0' for a floating-point signed zero", .{}),
                            });
                        } else {
                            try ig.addErrorTok(tok, "integer pk underflows u32 range", .{});
                        }
                    } else |err| switch (err) {
                        error.Overflow => try ig.addErrorTok(tok, "integer pk underflows u32 range", .{}),
                        error.InvalidCharacter => try ig.addErrorTok(tok, "invalid character in integer pk", .{}),
                    }
                },
                .identifier => {
                    if (mem.eql(u8, child_slice, "inf")) {
                        try ig.addErrorTok(tok, "'inf' can be only represented by floats; cannot be used for negation with u32", .{});
                    }
                },
                else => try ig.addErrorTok(tok, "expected integer pk after '-'", .{}),
            }
        },
        else => try ig.addErrorTok(tok, "expected enum literal or integer pk", .{}),
    }
    return null;
}

fn resolveNumber(ig: *IrGen, node: Tree.Node.Index) Allocator.Error!?Ir.Number {
    const tree = ig.tree;
    const id = tree.nodeId(node);
    const tok = tree.nodeMainToken(node);
    const slice = tree.tokenSlice(tok);

    switch (id) {
        .number_literal => if (std.fmt.parseFloat(f64, slice)) |num| return .fromFloat(num) else |err| switch (err) {
            error.InvalidCharacter => try ig.addErrorTok(tok, "invalid number literal", .{}),
        },
        .negation => {
            const child_node = tree.nodeData(node).node;
            const child_slice = tree.tokenSlice(tree.nodeMainToken(child_node));
            switch (tree.nodeId(child_node)) {
                .number_literal => if (std.fmt.parseFloat(f64, child_slice)) |num| return .fromFloat(-num) else |err| switch (err) {
                    error.InvalidCharacter => try ig.addErrorTok(tok, "invalid number literal", .{}),
                },
                // `parseFloat` handles the strings `inf` and `nan`, which are valid in ZON.
                // Effects with a value of either infinity or NaN do not make sense,
                // therefore the compiler throws an error.
                //
                // If any infinities or NaNs manage to make their way into the JS output after emission,
                // it is a compiler bug. Accounting for values that evaluate to either infinity or NaN
                // will be done soon.
                .identifier => if (std.fmt.parseFloat(f64, child_slice)) |float| {
                    if (std.math.isInf(float)) {
                        try ig.addErrorTok(tok, "infinities are not supported", .{});
                    } else if (std.math.isNan(float)) {
                        try ig.addErrorTok(tok, "NaNs are not supported", .{});
                    }
                } else |err| switch (err) {
                    error.InvalidCharacter => {},
                },
                else => try ig.addErrorTok(tok, "expected number after '-'", .{}),
            }
        },
        else => try ig.addErrorTok(tok, "expected number literal", .{}),
    }

    return null;
}

fn resolveArray(ig: *IrGen, buf: *[2]Tree.Node.Index, node: Tree.Node.Index) ![]const Tree.Node.Index {
    const tree = ig.tree;
    if (tree.fullArrayInit(buf, node)) |full| {
        return full.tree.elements;
    } else if (tree.fullStructInit(buf, node)) |_| {
        // In Zig, `.{}` is ambiguous. This can represent either an empty array or an empty struct.
        // In parsing, this is given a node id of `struct_init_dot_two`.
        switch (tree.nodeId(node)) {
            // Fall through to the `return`
            .struct_init_dot_two => {},
            else => try ig.addErrorNode(node, "expected an array", .{}),
        }
    }

    return &.{};
}

fn lowerQuestions(ig: *IrGen, payload: *Ir.Payload.Wip, qn_node: Tree.Node.Index) !void {
    const gpa = ig.gpa;
    const tree = ig.tree;

    var qn_buf: [2]Tree.Node.Index = undefined;
    const qn_full = try ig.resolveArray(&qn_buf, qn_node);

    for (qn_full) |qn_elem_node| {
        const qn = try ig.parseStruct(Question, qn_elem_node);
        const qn_idx: u32 = @intCast(payload.questions.items.len);

        if (qn.name) |name_node| {
            const node_id = tree.nodeId(name_node);
            if (node_id != .string_literal and node_id != .multiline_string_literal) {
                try ig.addErrorNode(name_node, "expected string literal", .{});
            } else if (ig.strLitAsString(name_node)) |res| switch (res) {
                .nts => |nts| try payload.symbols.append(gpa, .{
                    .kind = .question,
                    .idx = qn_idx,
                    .name = nts,
                }),
                .slice => |slice| try ig.verifySlice(slice, name_node),
            } else |err| switch (err) {
                error.BadString => {},
                error.OutOfMemory => |e| return e,
            }
        }

        const qn_text: Ir.NullTerminatedString = blk: {
            if (qn.text) |text_node| {
                const node_id = tree.nodeId(text_node);
                if (node_id != .string_literal and node_id != .multiline_string_literal) {
                    try ig.addErrorNode(text_node, "expected string literal", .{});
                } else if (ig.strLitAsString(text_node)) |res| switch (res) {
                    .nts => |nts| break :blk nts,
                    .slice => |slice| try ig.verifySlice(slice, text_node),
                } else |err| switch (err) {
                    error.BadString => {},
                    error.OutOfMemory => |e| return e,
                }
            } else {
                try ig.addErrorNode(qn_elem_node, "question requires 'text' field", .{});
            }
            break :blk .empty;
        };

        try payload.questions.append(gpa, .{ .text = qn_text });

        if (qn.answers) |ans_node| {
            var ans_buf: [2]Tree.Node.Index = undefined;
            const ans_full = try ig.resolveArray(&ans_buf, ans_node);

            for (ans_full) |ans_elem_node| {
                const ans = try ig.parseStruct(Answer, ans_elem_node);
                const ans_idx: u32 = @intCast(payload.answers.items.len);

                if (ans.name) |name_node| {
                    const node_id = tree.nodeId(name_node);
                    if (node_id != .string_literal and node_id != .multiline_string_literal) {
                        try ig.addErrorNode(name_node, "expected string literal", .{});
                    } else if (ig.strLitAsString(name_node)) |res| switch (res) {
                        .nts => |nts| try payload.symbols.append(gpa, .{ .kind = .answer, .idx = ans_idx, .name = nts }),
                        .slice => |slice| try ig.verifySlice(slice, name_node),
                    } else |err| switch (err) {
                        error.BadString => {},
                        error.OutOfMemory => |e| return e,
                    }
                }

                const ans_text: Ir.NullTerminatedString = blk: {
                    if (ans.text) |text_node| {
                        const node_id = tree.nodeId(text_node);
                        if (node_id != .string_literal and node_id != .multiline_string_literal) {
                            try ig.addErrorNode(text_node, "expected string literal", .{});
                        } else if (ig.strLitAsString(text_node)) |res| switch (res) {
                            .nts => |nts| break :blk nts,
                            .slice => |slice| try ig.verifySlice(slice, text_node),
                        } else |err| switch (err) {
                            error.BadString => {},
                            error.OutOfMemory => |e| return e,
                        }
                    } else {
                        try ig.addErrorNode(ans_elem_node, "answer requires 'text' field", .{});
                    }
                    break :blk .empty;
                };

                try payload.answers.append(gpa, .{
                    .qn = qn_idx,
                    .text = ans_text,
                });

                if (ans.feedback) |fdbk_node| {
                    try payload.feedbacks.append(gpa, .{
                        .ans = ans_idx,
                        .text = text: {
                            const node_id = tree.nodeId(fdbk_node);
                            if (node_id != .string_literal and node_id != .multiline_string_literal) {
                                try ig.addErrorNode(ans_elem_node, "expected string literal", .{});
                            } else if (ig.strLitAsString(fdbk_node)) |res| switch (res) {
                                .nts => |nts| break :text nts,
                                .slice => |slice| try ig.verifySlice(slice, fdbk_node),
                            } else |err| switch (err) {
                                error.BadString => {},
                                error.OutOfMemory => |e| return e,
                            }
                            break :text .empty;
                        },
                    });
                }

                if (ans.global_effects) |geff_node| {
                    var geff_buf: [2]Tree.Node.Index = undefined;
                    const geff_full = try ig.resolveArray(&geff_buf, geff_node);

                    for (geff_full) |geff_elem_node| {
                        const eff = try ig.parseStruct(Effect, geff_elem_node);

                        const tgt_pk: u32 = blk: {
                            if (eff.target) |tgt_node| {
                                if (try ig.resolvePk(tgt_node, &ig.candidates)) |tgt| {
                                    break :blk tgt;
                                }
                            } else {
                                try ig.addErrorNode(geff_elem_node, "global effect requires 'target' field", .{});
                            }
                            break :blk 0;
                        };

                        const mult: Ir.Number = blk: {
                            if (eff.effect) |mult_node| {
                                if (try ig.resolveNumber(mult_node)) |mult| break :blk mult;
                            } else {
                                try ig.addErrorNode(geff_elem_node, "global effect requires 'effect' field", .{});
                            }
                            break :blk .fromFloat(0);
                        };

                        try payload.global_effects.append(gpa, .{
                            .ans = ans_idx,
                            .tgt = tgt_pk,
                            .mult = mult,
                        });
                    }
                }

                if (ans.state_effects) |seff_node| {
                    var seff_buf: [2]Tree.Node.Index = undefined;
                    const seff_full = try ig.resolveArray(&seff_buf, seff_node);

                    for (seff_full) |seff_elem_node| {
                        const seff = try ig.parseStruct(StateEffect, seff_elem_node);

                        const state_pk: u32 = blk: {
                            if (seff.state) |state_node| {
                                if (try ig.resolvePk(state_node, &ig.states)) |state| {
                                    break :blk state;
                                }
                            } else {
                                try ig.addErrorNode(seff_elem_node, "issue effect requires 'issue' field", .{});
                            }
                            break :blk 0;
                        };

                        if (seff.effects) |effs_node| {
                            var effs_buf: [2]Tree.Node.Index = undefined;
                            const effs_full = try ig.resolveArray(&effs_buf, effs_node);

                            for (effs_full) |effs_elem_node| {
                                const eff = try ig.parseStruct(Effect, effs_elem_node);

                                const tgt_pk: u32 = blk: {
                                    if (eff.target) |tgt_node| {
                                        if (try ig.resolvePk(tgt_node, &ig.candidates)) |tgt| {
                                            break :blk tgt;
                                        }
                                    } else {
                                        try ig.addErrorNode(effs_elem_node, "effect requires 'target' field", .{});
                                    }
                                    break :blk 0;
                                };

                                const mult: Ir.Number = blk: {
                                    if (eff.effect) |mult_node| {
                                        if (try ig.resolveNumber(mult_node)) |mult| break :blk mult;
                                    } else {
                                        try ig.addErrorNode(effs_elem_node, "effect requires 'effect' field", .{});
                                    }
                                    break :blk .fromFloat(0);
                                };

                                try payload.state_effects.append(gpa, .{
                                    .state = state_pk,
                                    .eff = .{
                                        .ans = ans_idx,
                                        .tgt = tgt_pk,
                                        .mult = mult,
                                    },
                                });
                            }
                        } else {
                            try ig.addErrorNode(seff_elem_node, "state effect requires 'effects' field", .{});
                        }
                    }
                }

                if (ans.issue_effects) |ieff_node| {
                    var ieff_buf: [2]Tree.Node.Index = undefined;
                    const ieff_full = try ig.resolveArray(&ieff_buf, ieff_node);

                    for (ieff_full) |ieff_elem_node| {
                        const ieff = try ig.parseStruct(IssueEffect, ieff_elem_node);

                        const tgt_resolved: Ir.Payload.IssueEffect.TgtUnion = t: {
                            if (ieff.target) |target| {
                                const tgt = try ig.parseStruct(IssueTarget, target);
                                if (tgt.candidate != null and tgt.state != null) {
                                    const cand_ident = ig.tree.firstToken(tgt.candidate.?) - 2;
                                    const state_ident = ig.tree.firstToken(tgt.state.?) - 2;
                                    try ig.addErrorTokNotes(cand_ident, "target cannot have both 'candidate' and 'state' fields active", .{}, &.{
                                        try ig.errNoteTok(state_ident, "'state' field active here", .{}),
                                    });
                                }
                                if (tgt.candidate) |cand| {
                                    if (try ig.resolvePk(cand, &ig.candidates)) |pk| {
                                        break :t .{ .cand = pk };
                                    }
                                }
                                if (tgt.state) |state| {
                                    if (try ig.resolvePk(state, &ig.states)) |pk| {
                                        break :t .{ .state = pk };
                                    }
                                }
                            }
                            break :t .{ .cand = null };
                        };

                        const iss_pk: u32 = blk: {
                            if (ieff.issue) |iss_node| {
                                if (try ig.resolvePk(iss_node, &ig.issues)) |iss| {
                                    break :blk iss;
                                }
                            } else {
                                try ig.addErrorNode(ieff_elem_node, "issue effect requires 'issue' field", .{});
                            }
                            break :blk 0;
                        };

                        const score: Ir.Number = blk: {
                            if (ieff.score) |score_node| {
                                if (try ig.resolveNumber(score_node)) |score| break :blk score;
                            } else {
                                try ig.addErrorNode(ieff_elem_node, "issue effect requires 'score' field", .{});
                            }
                            break :blk .fromFloat(0);
                        };

                        const impt: Ir.Number = blk: {
                            if (ieff.importance) |impt_node| {
                                if (try ig.resolveNumber(impt_node)) |impt| break :blk impt;
                            } else {
                                try ig.addErrorNode(ieff_elem_node, "issue effect requires 'importance' field", .{});
                            }
                            break :blk .fromFloat(0);
                        };

                        try payload.issue_effects.append(gpa, .{
                            .ans = ans_idx,
                            .issue = iss_pk,
                            .score = score,
                            .impt = impt,
                            .tgt = tgt_resolved,
                        });
                    }
                }
            }
        } else {
            try ig.addErrorNode(qn_elem_node, "question requires 'answers' field", .{});
        }
    }
}

fn verifySlice(ig: *IrGen, slice: StringLiteralResult.Slice, node: Tree.Node.Index) !void {
    const raw_str = ig.string_bytes.items[slice.start..slice.len];
    if (mem.findScalar(u8, raw_str, 0)) |_| {
        return ig.addErrorNode(node, "string cannot contain null bytes", .{});
    } else if (slice.len == 0) {
        return ig.addErrorNode(node, "string cannot be empty", .{});
    }
}

const Definitions = struct {
    candidates: ?Tree.Node.Index = null,
    states: ?Tree.Node.Index = null,
    issues: ?Tree.Node.Index = null,
};

const Question = struct {
    name: ?Tree.Node.Index = null,
    text: ?Tree.Node.Index = null,
    answers: ?Tree.Node.Index = null,
};

const Answer = struct {
    name: ?Tree.Node.Index = null,
    text: ?Tree.Node.Index = null,
    feedback: ?Tree.Node.Index = null,
    global_effects: ?Tree.Node.Index = null,
    state_effects: ?Tree.Node.Index = null,
    issue_effects: ?Tree.Node.Index = null,
};

const Feedback = struct {
    text: ?Tree.Node.Index,
};

const Effect = struct {
    target: ?Tree.Node.Index = null,
    effect: ?Tree.Node.Index = null,
};

const StateEffect = struct {
    state: ?Tree.Node.Index = null,
    effects: ?Tree.Node.Index = null,
};

const IssueEffect = struct {
    target: ?Tree.Node.Index = null,
    issue: ?Tree.Node.Index = null,
    score: ?Tree.Node.Index = null,
    importance: ?Tree.Node.Index = null,
};

const IssueTarget = struct {
    state: ?Tree.Node.Index = null,
    candidate: ?Tree.Node.Index = null,
};

fn errNoteNode(
    ig: *IrGen,
    node: Tree.Node.Index,
    comptime fmt: []const u8,
    args: anytype,
) Allocator.Error!Ir.CompileError.Note {
    const msg_idx: u32 = @intCast(ig.string_bytes.items.len);
    try ig.string_bytes.print(ig.gpa, fmt ++ "\x00", args);
    return .{
        .msg = @fromBackingInt(msg_idx),
        .token = .none,
        .node_or_offset = @backingInt(node),
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
        .msg = @fromBackingInt(msg_idx),
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
    return ig.addErrorInner(.none, @backingInt(node), fmt, args, &.{});
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
    return ig.addErrorInner(.none, @backingInt(node), fmt, args, notes);
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

fn addErrorTokNotesOff(
    ig: *IrGen,
    tok: Tree.TokenIndex,
    offset: u32,
    comptime fmt: []const u8,
    args: anytype,
    notes: []const Ir.CompileError.Note,
) Allocator.Error!void {
    return ig.addErrorInner(.fromToken(tok), offset, fmt, args, notes);
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
        .msg = @fromBackingInt(msg_idx),
        .token = token,
        .node_or_offset = node_or_offset,
        .first_note = first_note,
        .note_count = @intCast(notes.len),
    });
}

fn lowerAstErrors(ig: *IrGen) Allocator.Error!void {
    const gpa = ig.gpa;
    const tree = ig.tree;
    assert(tree.errors.len > 0);

    var msg: Writer.Allocating = .init(gpa);
    defer msg.deinit();
    const msg_bw = &msg.writer;

    var notes: std.ArrayList(Ir.CompileError.Note) = .empty;
    defer notes.deinit(gpa);

    var cur_err = tree.errors[0];
    for (tree.errors[1..]) |err| {
        if (err.is_note) {
            tree.renderError(err, msg_bw) catch |er| switch (er) {
                error.WriteFailed => return error.OutOfMemory,
            };
            try notes.append(gpa, try ig.errNoteTok(err.token, "{s}", .{msg.written()}));
        } else {
            tree.renderError(cur_err, msg_bw) catch |er| switch (er) {
                error.WriteFailed => return error.OutOfMemory,
            };
            const extra_offset = tree.errorOffset(cur_err);
            try ig.addErrorTokNotesOff(cur_err.token, extra_offset, "{s}", .{msg.written()}, notes.items);
            notes.clearRetainingCapacity();
            cur_err = err;

            return;
        }
        msg.clearRetainingCapacity();
    }

    const extra_offset = tree.errorOffset(cur_err);
    tree.renderError(cur_err, msg_bw) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
    };
    try ig.addErrorTokNotesOff(cur_err.token, extra_offset, "{s}", .{msg.written()}, notes.items);
}

fn suggest(ig: *IrGen, str: []const u8, table: *const SymbolTable) Ir.NullTerminatedString {
    var bfa_buf: [256]u8 = undefined;
    var bfa: std.heap.BufferFirstAllocator = .init(&bfa_buf, ig.gpa);
    const gpa = bfa.allocator();

    var nearest_match: Ir.NullTerminatedString = .empty;
    var min_dist: u32 = 4;

    var it = table.keyIterator();
    while (it.next()) |key_ptr| {
        const key = key_ptr.*;
        const raw: Ir.NullTerminatedString = @fromBackingInt(key);
        const dist = lev(gpa, str, raw.getAny(ig.string_bytes.items)) catch continue;
        if (dist < min_dist) {
            min_dist = dist;
            nearest_match = @fromBackingInt(key);
        }
    }

    return nearest_match;
}

fn lev(gpa: Allocator, a: []const u8, b: []const u8) !u32 {
    if (a.len < b.len) return lev(gpa, b, a);
    if (b.len == 0) return @intCast(a.len);

    const row = try gpa.alloc(u32, b.len + 1);
    defer gpa.free(row);

    for (row, 0..) |*val, i| {
        val.* = @intCast(i);
    }

    for (a) |c| {
        var prev = row[0];
        row[0] += 1;

        for (1..row.len) |j| {
            const old = row[j];
            const cost: u32 = if (c == b[j - 1]) 0 else 1;

            row[j] = @min(
                row[j] + 1,
                row[j - 1] + 1,
                prev + cost,
            );
            prev = old;
        }
    }
    return row[b.len];
}
