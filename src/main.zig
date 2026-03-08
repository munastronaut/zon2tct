const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;

const SymbolTable = struct {
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
            const category_name = getFieldName(ast, val_node_idx);

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
                const item_name = getFieldName(ast, item_node_idx);

                const val_str = ast.tokenSlice(item_main_tok);
                const val = try std.fmt.parseInt(i32, val_str, 10);

                const key = try allocator.dupe(u8, item_name);
                try target_map.put(key, val);
            }
        }
    }
};

const STARTING_Q_PK = 400;
const STARTING_A_PK = 1000;
const STARTING_F_PK = 5000;
const STARTING_GE_PK = 8000;
const STARTING_SE_PK = 10000;
const STARTING_IE_PK = 12000;

const Transpiler = struct {
    const Self = @This();

    arena: *std.heap.ArenaAllocator,
    allocator: Allocator,
    symbols: *SymbolTable,
    player_id: []const u8,

    questions: std.ArrayList(u8),
    answers: std.ArrayList(u8),
    global_effects: std.ArrayList(u8),
    state_effects: std.ArrayList(u8),
    issue_effects: std.ArrayList(u8),
    feedbacks: std.ArrayList(u8),

    q_pk: i32 = STARTING_Q_PK,
    a_pk: i32 = STARTING_A_PK,
    f_pk: i32 = STARTING_F_PK,
    ge_pk: i32 = STARTING_GE_PK,
    se_pk: i32 = STARTING_SE_PK,
    ie_pk: i32 = STARTING_IE_PK,

    pub fn init(arena: *std.heap.ArenaAllocator, symbols: *SymbolTable) Self {
        return .{
            .arena = arena,
            .allocator = arena.allocator(),
            .symbols = symbols,
            .player_id = "e.candidate_id",
            .questions = .empty,
            .answers = .empty,
            .global_effects = .empty,
            .state_effects = .empty,
            .issue_effects = .empty,
            .feedbacks = .empty,
        };
    }

    // Incomplete functions beloww
    pub fn transpile(self: *Self, ast: *Ast, question_node: Ast.Node.Index) !void {
        var buffer: [2]Ast.Node.Index = undefined;
        const array = ast.fullArrayInit(&buffer, question_node) orelse return;

        for (array.ast.elements) |q_node| {
            try self.processQuestion(ast, q_node);
            self.q_pk += 1;
        }
    }

    fn processQuestion(self: *Self, ast: *Ast, q_node: Ast.Node.Index) !void {
        const q_id = self.q_pk;

        const q_text_node = findField(ast, q_node, "text") orelse return;
        const q_text = try getNodeString(self.allocator, ast, q_text_node);

        var escaped_desc = try escapeChars(self.allocator, q_text);
        defer escaped_desc.deinit(self.allocator);

        if (self.q_pk == STARTING_Q_PK) try self.questions.append(self.allocator, '\n');

        try self.questions.print(self.allocator,
            \\  {{
            \\    model: "campaign_trail.question",
            \\    pk: {d},
            \\    fields: {{
            \\      priority: 1,
            \\      description: "{s}",
            \\      likelihood: 1,
            \\    }},
            \\  }},
            \\
        , .{ q_id, escaped_desc.items });

        const answers_node = findField(ast, q_node, "answers") orelse return;
        var buffer: [2]Ast.Node.Index = undefined;
        const answers_array = ast.fullArrayInit(&buffer, answers_node) orelse return;

        for (answers_array.ast.elements) |a_node| {
            try self.processAnswer(ast, a_node, q_id);
            self.a_pk += 1;
        }
    }

    fn processAnswer(self: *Self, ast: *Ast, a_node: Ast.Node.Index, q_id: i32) !void {
        const a_id = self.a_pk;

        const a_text_node = findField(ast, a_node, "text") orelse return;
        const a_text = try getNodeString(self.allocator, ast, a_text_node);

        var escaped_answer = try escapeChars(self.allocator, a_text);
        defer escaped_answer.deinit(self.allocator);

        if (self.a_pk == STARTING_A_PK) try self.answers.append(self.allocator, '\n');

        try self.answers.print(self.allocator,
            \\  {{
            \\    model: "campaign_trail.answer",
            \\    pk: {d},
            \\    fields: {{
            \\      question: {d},
            \\      description: "{s}",
            \\    }},
            \\  }},
            \\
        , .{ a_id, q_id, escaped_answer.items });

        if (findField(ast, a_node, "feedback")) |f_node| {
            const feedback_text = try getNodeString(self.allocator, ast, f_node);

            var escaped_feedback = try escapeChars(self.allocator, feedback_text);
            defer escaped_feedback.deinit(self.allocator);

            if (self.f_pk == STARTING_F_PK) try self.feedbacks.append(self.allocator, '\n');

            try self.feedbacks.print(self.allocator,
                \\  {{
                \\    model: "campaign_trail.answer_feedback",
                \\    pk: {d},
                \\    fields: {{
                \\      answer: {d},
                \\      candidate: {s},
                \\      answer_feedback: "{s}",
                \\    }},
                \\  }},
                \\
            , .{ self.f_pk, a_id, self.player_id, escaped_feedback.items });
            self.f_pk += 1;
        }

        if (findField(ast, a_node, "global_effects")) |ge_node| {
            var buffer: [2]Ast.Node.Index = undefined;
            const array = ast.fullArrayInit(&buffer, ge_node) orelse return;

            if (self.ge_pk == STARTING_GE_PK) try self.global_effects.append(self.allocator, '\n');

            for (array.ast.elements) |eff_node| {
                const target_node = findField(ast, eff_node, "target") orelse {
                    const loc = getNodeLocation(ast, eff_node);
                    std.process.fatal("no target for global effect! line {d}:{d}", .{ loc.line, loc.column });
                    continue;
                };
                const effect_node = findField(ast, eff_node, "effect") orelse {
                    const loc = getNodeLocation(ast, eff_node);
                    std.process.fatal("no effect for global effect! line {d}:{d}", .{ loc.line, loc.column });
                    continue;
                };

                const target_id = try self.resolveId(ast, target_node);
                const raw_effect = getNodeSource(ast, effect_node);

                try self.global_effects.print(self.allocator,
                    \\  {{
                    \\    model: "campaign_trail.answer_score_global",
                    \\    pk: {d},
                    \\    fields: {{
                    \\      answer: {d},
                    \\      candidate: {s},
                    \\      affected_candidate: {d},
                    \\      global_multiplier: {s},
                    \\    }},
                    \\  }},
                    \\
                , .{ self.ge_pk, a_id, self.player_id, target_id, raw_effect });
                self.ge_pk += 1;
            }
        }

        if (findField(ast, a_node, "state_effects")) |se_node| {
            var buffer: [2]Ast.Node.Index = undefined;
            const array = ast.fullArrayInit(&buffer, se_node) orelse return;

            if (self.se_pk == STARTING_SE_PK) try self.state_effects.append(self.allocator, '\n');

            for (array.ast.elements) |eff_node| {
                const state_node = findField(ast, eff_node, "state") orelse continue;
                const state_id = try self.resolveId(ast, state_node);

                var buf: [2]Ast.Node.Index = undefined;
                const effects_node = findField(ast, eff_node, "effects") orelse continue;
                const eff_arr = ast.fullArrayInit(&buf, effects_node) orelse return;

                for (eff_arr.ast.elements) |sef_node| {
                    const target_node = findField(ast, sef_node, "target") orelse continue;
                    const effect_node = findField(ast, sef_node, "effect") orelse continue;

                    const target_id = try self.resolveId(ast, target_node);
                    const raw_effect = getNodeSource(ast, effect_node);

                    try self.state_effects.print(self.allocator,
                        \\  {{
                        \\    model: "campaign_trail.answer_score_state",
                        \\    pk: {d},
                        \\    fields: {{
                        \\      answer: {d},
                        \\      state: {d},
                        \\      candidate: {s},
                        \\      affected_candidate: {d},
                        \\      state_multiplier: {s},
                        \\    }},
                        \\  }},
                        \\
                    , .{ self.se_pk, a_id, state_id, self.player_id, target_id, raw_effect });
                    self.se_pk += 1;
                }
            }
        }

        if (findField(ast, a_node, "issue_effects")) |ie_node| {
            var buffer: [2]Ast.Node.Index = undefined;
            const array = ast.fullArrayInit(&buffer, ie_node) orelse return;

            if (self.ie_pk == STARTING_IE_PK) try self.issue_effects.append(self.allocator, '\n');

            for (array.ast.elements) |eff_node| {
                const issue_node = findField(ast, eff_node, "issue") orelse continue;
                const score_node = findField(ast, eff_node, "score") orelse continue;
                const importance_node = findField(ast, eff_node, "importance") orelse continue;

                const issue_id = try self.resolveId(ast, issue_node);
                const raw_effect = getNodeSource(ast, score_node);
                const raw_importance = getNodeSource(ast, importance_node);

                try self.issue_effects.print(self.allocator,
                    \\  {{
                    \\    model: "campaign_trail.candidate_issue_score",
                    \\    pk: {d},
                    \\    fields: {{
                    \\      answer: {d},
                    \\      issue: {d},
                    \\      issue_score: {s},
                    \\      issue_importance: {s},
                    \\    }},
                    \\  }},
                    \\
                , .{ self.ie_pk, a_id, issue_id, raw_effect, raw_importance });
            }
        }
    }

    fn resolveId(self: *Self, ast: *Ast, node: Ast.Node.Index) !i32 {
        const tag: Ast.Node.Tag = ast.nodes.items(.tag)[@intFromEnum(node)];
        const tok: Ast.TokenIndex = ast.nodes.items(.main_token)[@intFromEnum(node)];
        const slice = ast.tokenSlice(tok);

        if (tag == .enum_literal) {
            const key = if (slice[0] == '.') slice[1..] else slice;

            if (self.symbols.candidates.get(key)) |val| return val;
            if (self.symbols.states.get(key)) |val| return val;
            if (self.symbols.issues.get(key)) |val| return val;

            std.log.err("undefined alias used: .{s}", .{key});
            return error.UndefinedAlias;
        }

        return std.fmt.parseInt(i32, slice, 10) catch 0;
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("Usage: {s} <input> [output]\n", .{args[0]});
        return;
    }

    const input_path = args[1];
    const output_path = if (args.len > 2) args[2] else "code2.js";

    const src = try Io.Dir.cwd().readFileAllocOptions(init.io, input_path, allocator, .limited(10 * 1024 * 1024), .@"8", 0);
    defer allocator.free(src);

    var ast = try Ast.parse(allocator, src, .zon);
    defer ast.deinit(allocator);

    const root_data = ast.nodes.items(.data)[0];
    const root_expr_idx = root_data.node;

    var symbols = SymbolTable.init(allocator);
    defer symbols.deinit();

    var transpiler = Transpiler.init(init.arena, &symbols);

    if (findField(&ast, root_expr_idx, "definitions")) |defs_node|
        try symbols.populateTable(arena, &ast, defs_node);

    if (findField(&ast, root_expr_idx, "player_candidate")) |pc_node| {
        const id = try transpiler.resolveId(&ast, pc_node);
        transpiler.player_id = try std.fmt.allocPrint(arena, "{d}", .{id});
    }

    if (findField(&ast, root_expr_idx, "questions")) |questions_node|
        try transpiler.transpile(&ast, questions_node);

    const output_file = try Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer output_file.close(init.io);

    var output_buffer: [4096]u8 = undefined;
    var writer = output_file.writer(init.io, &output_buffer);
    var output_writer = &writer.interface;

    try output_writer.print(
        \\e = campaignTrail_temp;
        \\
        \\e.questions_json = [{s}];
        \\
        \\e.answers_json = [{s}];
        \\
        // States json here
        // Issues json here
        // State issue scores json here
        // Candidate issue scores json here
        // Running mate issue scores json here
        // Candidate state multiplier json here
        \\e.answer_score_global_json = [{s}];
        \\
        \\e.answer_score_issue_json = [{s}];
        \\
        \\e.answer_score_state_json = [{s}];
        \\
        \\e.answer_feedback_json = [{s}];
        \\
    , .{ transpiler.questions.items, transpiler.answers.items, transpiler.global_effects.items, transpiler.issue_effects.items, transpiler.state_effects.items, transpiler.feedbacks.items });
    try output_writer.flush();
}

fn getFieldName(ast: *Ast, val_node_idx: Ast.Node.Index) []const u8 {
    const val_main_tok = ast.nodes.items(.main_token)[@intFromEnum(val_node_idx)];
    var t = val_main_tok - 1;
    while (t > 0) : (t -= 1)
        if (ast.tokens.items(.tag)[t] == .identifier) break;

    return ast.tokenSlice(t);
}

fn findField(ast: *Ast, struct_node: Ast.Node.Index, target_name: []const u8) ?Ast.Node.Index {
    var buffer: [2]Ast.Node.Index = undefined;
    const info = ast.fullStructInit(&buffer, struct_node) orelse return null;
    for (info.ast.fields) |f_node|
        if (std.mem.eql(u8, getFieldName(ast, f_node), target_name)) return f_node;
    return null;
}

fn escapeChars(allocator: Allocator, input: []const u8) !std.ArrayList(u8) {
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

fn unescapeString(allocator: Allocator, input: []const u8) ![]const u8 {
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

fn getNodeString(allocator: Allocator, ast: *Ast, node: Ast.Node.Index) ![]const u8 {
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

fn getNodeSource(ast: *Ast, node: Ast.Node.Index) []const u8 {
    const first_tok = ast.firstToken(node);
    const last_tok = ast.lastToken(node);
    const start = ast.tokens.items(.start)[first_tok];

    const last_tok_slice = ast.tokenSlice(last_tok);
    const end = ast.tokens.items(.start)[last_tok] + last_tok_slice.len;

    return ast.source[start..end];
}

fn getNodeLocation(ast: *Ast, node: Ast.Node.Index) struct { line: usize, column: usize } {
    const main_toks = ast.nodes.items(.main_token);
    const tok_idx = main_toks[@intFromEnum(node)];
    const loc = ast.tokenLocation(0, tok_idx);
    return .{
        .line = loc.line + 1,
        .column = loc.column + 1,
    };
}
