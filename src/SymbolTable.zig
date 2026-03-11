const std = @import("std");
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;
const ErrorCollector = @import("ErrorCollector.zig");
const common = @import("common.zig");

const Self = @This();

candidates: std.StringHashMap(i32),
states: std.StringHashMap(i32),
issues: std.StringHashMap(i32),
manifest: std.StringHashMap(i32),

pub fn init(allocator: Allocator) Self {
    return .{
        .candidates = .init(allocator),
        .states = .init(allocator),
        .issues = .init(allocator),
        .manifest = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.candidates.deinit();
    self.states.deinit();
    self.issues.deinit();
    self.manifest.deinit();
}

pub fn populateTable(self: *Self, allocator: Allocator, ast: *Ast, defs_node: Ast.Node.Index, collector: *ErrorCollector) !void {
    var buffer: [2]Ast.Node.Index = undefined;
    const defs_info = ast.fullStructInit(&buffer, defs_node) orelse return;

    for (defs_info.ast.fields) |val_node_idx| {
        const category_name = common.getFieldName(ast, val_node_idx);

        var target_map: *std.StringHashMap(i32) = if (std.mem.eql(u8, category_name, "states"))
            &self.states
        else if (std.mem.eql(u8, category_name, "candidates"))
            &self.candidates
        else if (std.mem.eql(u8, category_name, "issues"))
            &self.issues
        else
            continue;

        var item_buffer: [2]Ast.Node.Index = undefined;
        const category_info = ast.fullStructInit(&item_buffer, val_node_idx) orelse continue;

        for (category_info.ast.fields) |item_node_idx| {
            const item_main_tok = ast.nodes.items(.main_token)[@intFromEnum(item_node_idx)];
            const item_name = common.getFieldName(ast, item_node_idx);

            if (target_map.contains(item_name)) {
                const start_tok = common.getFieldStartToken(ast, item_node_idx);
                const name_tok = common.getFieldNameToken(ast, item_node_idx);

                const tok_starts = ast.tokens.items(.start);
                const start_offset = tok_starts[start_tok];
                const name_offset = tok_starts[name_tok];
                const name_len = ast.tokenSlice(name_tok).len;

                const report_len = (name_offset - start_offset) + name_len;

                const loc_info = ast.tokenLocation(0, start_tok);
                const loc: common.Location = .{ .line = loc_info.line + 1, .column = loc_info.column + 1 };

                const msg = try std.fmt.allocPrint(allocator, "duplicate alias definition: '.{s}'", .{item_name});
                try collector.report(.@"error", .underline, loc, report_len, msg, null);
                continue;
            }

            const val_str = ast.tokenSlice(item_main_tok);
            const val = try std.fmt.parseInt(i32, val_str, 10);

            const key = try allocator.dupe(u8, item_name);
            try target_map.put(key, val);
        }
    }
}

fn lev(allocator: Allocator, a: []const u8, b: []const u8) !usize {
    if (a.len < b.len) return lev(allocator, b, a);
    if (b.len == 0) return a.len;

    const row = try allocator.alloc(usize, b.len + 1);
    defer allocator.free(row);

    for (row, 0..) |*val, i|
        val.* = i;

    for (a) |char_a| {
        var prev_diag = row[0];
        row[0] += 1;

        for (1..row.len) |j| {
            const old_row_j = row[j];
            const cost: usize = if (char_a == b[j - 1]) 0 else 1;

            row[j] = @min(
                row[j] + 1,
                row[j - 1] + 1,
                prev_diag + cost,
            );
            prev_diag = old_row_j;
        }
    }
    return row[b.len];
}

pub fn findSuggestion(self: *Self, allocator: Allocator, typo: []const u8, context: common.Context) ?[]const u8 {
    var nearest_match: ?[]const u8 = null;
    var min_dist: usize = 4;

    const map = switch (context) {
        .candidates => &self.candidates,
        .states => &self.states,
        .issues => &self.issues,
    };

    var it = map.keyIterator();
    while (it.next()) |key_p| {
        const key = key_p.*;
        const dist = lev(allocator, typo, key) catch continue;
        if (dist < min_dist) {
            min_dist = dist;
            nearest_match = key;
        }
    }

    return nearest_match;
}
