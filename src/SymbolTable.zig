const std = @import("std");
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;
const common = @import("common.zig");

const Self = @This();

candidates: std.StringHashMap(i32),
states: std.StringHashMap(i32),
issues: std.StringHashMap(i32),

pub fn init(allocator: Allocator) Self {
    return .{
        .candidates = .init(allocator),
        .states = .init(allocator),
        .issues = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.candidates.deinit();
    self.states.deinit();
    self.issues.deinit();
}

pub fn populateTable(self: *Self, allocator: Allocator, ast: *Ast, defs_node: Ast.Node.Index) !void {
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

            const val_str = ast.tokenSlice(item_main_tok);
            const val = try std.fmt.parseInt(i32, val_str, 10);

            const key = try allocator.dupe(u8, item_name);
            try target_map.put(key, val);
        }
    }
}
