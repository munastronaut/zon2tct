const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;

pub const STARTING_Q_PK = 400;
pub const STARTING_A_PK = 1000;
pub const STARTING_F_PK = 5000;
pub const STARTING_GE_PK = 8000;
pub const STARTING_SE_PK = 10000;
pub const STARTING_IE_PK = 12000;

pub const Location = struct {
    line: usize,
    column: usize,
};

pub const Context = enum {
    candidates,
    states,
    issues,
};

pub fn getFieldName(ast: *Ast, val_node_idx: Ast.Node.Index) []const u8 {
    const val_main_tok = ast.nodes.items(.main_token)[@intFromEnum(val_node_idx)];
    var t = val_main_tok - 1;
    while (t > 0) : (t -= 1)
        if (ast.tokens.items(.tag)[t] == .identifier) break;

    return ast.tokenSlice(t);
}

pub fn getFieldNameToken(ast: *Ast, val_node_idx: Ast.Node.Index) Ast.TokenIndex {
    const val_main_tok = ast.nodes.items(.main_token)[@intFromEnum(val_node_idx)];
    var t = val_main_tok - 1;
    while (t > 0) : (t -= 1) {
        const tag = ast.tokens.items(.tag)[t];
        if (tag == .identifier)
            return t;
        if (tag == .comma or tag == .l_brace)
            break;
    }
    return val_main_tok;
}

pub fn getFieldStartToken(ast: *Ast, val_node_idx: Ast.Node.Index) Ast.TokenIndex {
    const val_main_tok = ast.nodes.items(.main_token)[@intFromEnum(val_node_idx)];
    var t = val_main_tok;
    while (t > 0) {
        t -= 1;
        const tag = ast.tokens.items(.tag)[t];
        if (tag == .period)
            return t;
        if (tag == .comma or tag == .l_brace)
            break;
    }
    return val_main_tok;
}

pub fn findField(ast: *Ast, struct_node: Ast.Node.Index, target_name: []const u8) ?Ast.Node.Index {
    var buffer: [2]Ast.Node.Index = undefined;
    const info = ast.fullStructInit(&buffer, struct_node) orelse return null;
    for (info.ast.fields) |f_node|
        if (std.mem.eql(u8, getFieldName(ast, f_node), target_name)) return f_node;
    return null;
}

pub fn escapeChars(allocator: Allocator, input: []const u8) !std.ArrayList(u8) {
    var list: std.ArrayList(u8) = .empty;
    for (input) |char| {
        switch (char) {
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\"' => try list.appendSlice(allocator, "\\\""),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => try list.append(allocator, char),
        }
    }
    return list;
}

pub fn unescapeString(allocator: Allocator, input: []const u8) ![]const u8 {
    if (input.len < 2) return try allocator.dupe(u8, "");
    const inner = input[1 .. input.len - 1];

    var res: std.ArrayList(u8) = .empty;
    errdefer res.deinit(allocator);

    var i: usize = 0;
    while (i < inner.len) {
        if (inner[i] == '\\') {
            i += 1;
            if (i >= inner.len) break;
            switch (inner[i]) {
                'n' => try res.append(allocator, '\n'),
                'r' => try res.append(allocator, '\r'),
                't' => try res.append(allocator, '\t'),
                '\\' => try res.append(allocator, '\\'),
                '\"' => try res.append(allocator, '\"'),
                '\'' => try res.append(allocator, '\''),
                'x' => {
                    if (i + 2 >= inner.len) return error.InvalidHexEscape;
                    const hex = inner[i + 1 .. i + 3];
                    const val = try std.fmt.parseInt(u8, hex, 16);
                    try res.append(allocator, val);
                    i += 2;
                },
                else => try res.append(allocator, inner[i]),
            }
        } else {
            try res.append(allocator, inner[i]);
        }
        i += 1;
    }
    return res.toOwnedSlice(allocator);
}

pub fn getNodeString(allocator: Allocator, ast: *Ast, node: Ast.Node.Index) ![]const u8 {
    const node_tags: []Ast.Node.Tag = ast.nodes.items(.tag);
    const tag = node_tags[@intFromEnum(node)];

    const main_toks: []Ast.TokenIndex = ast.nodes.items(.main_token);
    const main_tok_idx = main_toks[@intFromEnum(node)];
    const raw_bytes = ast.tokenSlice(main_toks[@intFromEnum(node)]);

    switch (tag) {
        .string_literal => {
            return try unescapeString(allocator, raw_bytes);
        },
        .enum_literal => {
            if (raw_bytes.len > 0 and raw_bytes[0] == '.') return try allocator.dupe(u8, raw_bytes[1..]);
            return try allocator.dupe(u8, raw_bytes);
        },
        .multiline_string_literal => {
            var list: std.ArrayList(u8) = .empty;
            errdefer list.deinit(allocator);

            var current_tok = main_tok_idx;
            const tok_tags = ast.tokens.items(.tag);

            while (current_tok < tok_tags.len) : (current_tok += 1) {
                if (tok_tags[current_tok] != .multiline_string_literal_line) break;

                const literal = ast.tokenSlice(current_tok);
                const content = if (literal.len >= 2) literal[2..] else "";

                try list.appendSlice(allocator, content);

                if (current_tok + 1 < tok_tags.len and tok_tags[current_tok + 1] == .multiline_string_literal_line)
                    try list.append(allocator, '\n');
            }
            return try list.toOwnedSlice(allocator);
        },
        else => {
            std.log.err("expected string or alias, found node tag: {any}", .{tag});
            return error.NotAString;
        },
    }
}

pub fn getNodeSource(ast: *Ast, node: Ast.Node.Index) []const u8 {
    const first_tok = ast.firstToken(node);
    const last_tok = ast.lastToken(node);
    const start = ast.tokens.items(.start)[first_tok];

    const last_tok_slice = ast.tokenSlice(last_tok);
    const end = ast.tokens.items(.start)[last_tok] + last_tok_slice.len;

    return ast.source[start..end];
}

pub fn getNodeLocation(ast: *Ast, node: Ast.Node.Index) Location {
    const main_toks = ast.nodes.items(.main_token);
    const tok_idx = main_toks[@intFromEnum(node)];
    const loc = ast.tokenLocation(0, tok_idx);
    return .{
        .line = loc.line + 1,
        .column = loc.column + 1,
    };
}

pub fn isValidJSIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name, 0..) |char, i| {
        if (i == 0 and std.ascii.isDigit(char))
            return false;
        if (!std.ascii.isAlphanumeric(char) and char != '_')
            return false;
    }
    return true;
}
