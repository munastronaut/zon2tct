const std = @import("std");
const Allocator = std.mem.Allocator;
const SymbolTable = @import("SymbolTable.zig");
const ErrorCollector = @import("ErrorCollector.zig");
const common = @import("common.zig");
const Ast = std.zig.Ast;

const Self = @This();

arena: *std.heap.ArenaAllocator,
allocator: Allocator,
symbols: *SymbolTable,
collector: *ErrorCollector,
player_id: []const u8,

questions: std.ArrayList(u8),
answers: std.ArrayList(u8),
global_effects: std.ArrayList(u8),
state_effects: std.ArrayList(u8),
issue_effects: std.ArrayList(u8),
feedbacks: std.ArrayList(u8),

q_pk: i32 = common.STARTING_Q_PK,
a_pk: i32 = common.STARTING_A_PK,
f_pk: i32 = common.STARTING_F_PK,
ge_pk: i32 = common.STARTING_GE_PK,
se_pk: i32 = common.STARTING_SE_PK,
ie_pk: i32 = common.STARTING_IE_PK,

pub fn init(arena: *std.heap.ArenaAllocator, symbols: *SymbolTable, collector: *ErrorCollector) Self {
    return .{
        .arena = arena,
        .allocator = arena.allocator(),
        .symbols = symbols,
        .collector = collector,
        .player_id = "e.candidate_id",
        .questions = .empty,
        .answers = .empty,
        .global_effects = .empty,
        .state_effects = .empty,
        .issue_effects = .empty,
        .feedbacks = .empty,
    };
}

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
    const q_loc = common.getNodeLocation(ast, q_node);

    const q_text_node = common.findField(ast, q_node, "text") orelse blk: {
        try self.collector.reportMissingField(q_loc, "question", "text");
        break :blk @as(Ast.Node.Index, @enumFromInt(0));
    };
    const q_text = try common.getNodeString(self.allocator, ast, q_text_node);

    var escaped_desc = try common.escapeChars(self.allocator, q_text);
    defer escaped_desc.deinit(self.allocator);

    if (self.q_pk == common.STARTING_Q_PK) try self.questions.append(self.allocator, '\n');

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

    const answers_node = common.findField(ast, q_node, "answers") orelse blk: {
        try self.collector.reportMissingField(q_loc, "question", "answers");
        break :blk @as(Ast.Node.Index, @enumFromInt(0));
    };
    var buffer: [2]Ast.Node.Index = undefined;
    const answers_array = ast.fullArrayInit(&buffer, answers_node) orelse return;

    for (answers_array.ast.elements) |a_node| {
        try self.processAnswer(ast, a_node, q_id);
        self.a_pk += 1;
    }
}

fn processAnswer(self: *Self, ast: *Ast, a_node: Ast.Node.Index, q_id: i32) !void {
    const a_id = self.a_pk;
    const a_loc = common.getNodeLocation(ast, a_node);

    const a_text_node = common.findField(ast, a_node, "text") orelse blk: {
        try self.collector.reportMissingField(a_loc, "answer", "text");
        break :blk @as(Ast.Node.Index, @enumFromInt(0));
    };
    const a_text = try common.getNodeString(self.allocator, ast, a_text_node);

    var escaped_answer = try common.escapeChars(self.allocator, a_text);
    defer escaped_answer.deinit(self.allocator);

    if (self.a_pk == common.STARTING_A_PK) try self.answers.append(self.allocator, '\n');

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

    if (common.findField(ast, a_node, "feedback")) |f_node| {
        const feedback_text = try common.getNodeString(self.allocator, ast, f_node);

        var escaped_feedback = try common.escapeChars(self.allocator, feedback_text);
        defer escaped_feedback.deinit(self.allocator);

        if (self.f_pk == common.STARTING_F_PK) try self.feedbacks.append(self.allocator, '\n');

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

    if (common.findField(ast, a_node, "global_effects")) |ge_node| {
        var buffer: [2]Ast.Node.Index = undefined;
        const array = ast.fullArrayInit(&buffer, ge_node) orelse return;

        if (self.ge_pk == common.STARTING_GE_PK) try self.global_effects.append(self.allocator, '\n');

        for (array.ast.elements) |eff_node| {
            const loc = common.getNodeLocation(ast, eff_node);
            const target_node = common.findField(ast, eff_node, "target") orelse blk: {
                try self.collector.reportMissingField(loc, "global effect", "target");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };
            const effect_node = common.findField(ast, eff_node, "effect") orelse blk: {
                try self.collector.reportMissingField(loc, "global effect", "effect");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };

            const target_id = try self.resolveId(ast, target_node, .candidates);
            const raw_effect = common.getNodeSource(ast, effect_node);
            const float_eff = std.fmt.parseFloat(f64, raw_effect) catch blk: {
                if (effect_node == @as(Ast.Node.Index, @enumFromInt(0)))
                    break :blk @as(f64, 0.0);
                try self.collector.reportFieldTypeMismatch(common.getNodeLocation(ast, effect_node), raw_effect.len, "global effect", "effect", "float");
                break :blk 0.0;
            };

            try self.global_effects.print(self.allocator,
                \\  {{
                \\    model: "campaign_trail.answer_score_global",
                \\    pk: {d},
                \\    fields: {{
                \\      answer: {d},
                \\      candidate: {s},
                \\      affected_candidate: {d},
                \\      global_multiplier: {d},
                \\    }},
                \\  }},
                \\
            , .{ self.ge_pk, a_id, self.player_id, target_id, float_eff });
            self.ge_pk += 1;
        }
    }

    if (common.findField(ast, a_node, "state_effects")) |se_node| {
        var buffer: [2]Ast.Node.Index = undefined;
        const array = ast.fullArrayInit(&buffer, se_node) orelse return;

        if (self.se_pk == common.STARTING_SE_PK) try self.state_effects.append(self.allocator, '\n');

        for (array.ast.elements) |eff_node| {
            const state_node = common.findField(ast, eff_node, "state") orelse continue;
            const state_id = try self.resolveId(ast, state_node, .states);

            var buf: [2]Ast.Node.Index = undefined;
            const effects_node = common.findField(ast, eff_node, "effects") orelse continue;
            const eff_arr = ast.fullArrayInit(&buf, effects_node) orelse return;

            for (eff_arr.ast.elements) |sef_node| {
                const sef_loc = common.getNodeLocation(ast, sef_node);
                const target_node = common.findField(ast, sef_node, "target") orelse blk: {
                    try self.collector.reportMissingField(sef_loc, "state effect", "target");
                    break :blk @as(Ast.Node.Index, @enumFromInt(0));
                };
                const effect_node = common.findField(ast, sef_node, "effect") orelse blk: {
                    try self.collector.reportMissingField(sef_loc, "state effect", "effect");
                    break :blk @as(Ast.Node.Index, @enumFromInt(0));
                };

                const target_id = try self.resolveId(ast, target_node, .candidates);
                const raw_effect = common.getNodeSource(ast, effect_node);
                const float_eff = std.fmt.parseFloat(f64, raw_effect) catch blk: {
                    if (effect_node == @as(Ast.Node.Index, @enumFromInt(0)))
                        break :blk @as(f64, 0.0);
                    try self.collector.reportFieldTypeMismatch(sef_loc, raw_effect.len, "state effect", "effect", "float");
                    break :blk 0.0;
                };

                try self.state_effects.print(self.allocator,
                    \\  {{
                    \\    model: "campaign_trail.answer_score_state",
                    \\    pk: {d},
                    \\    fields: {{
                    \\      answer: {d},
                    \\      state: {d},
                    \\      candidate: {s},
                    \\      affected_candidate: {d},
                    \\      state_multiplier: {d},
                    \\    }},
                    \\  }},
                    \\
                , .{ self.se_pk, a_id, state_id, self.player_id, target_id, float_eff });
                self.se_pk += 1;
            }
        }
    }

    if (common.findField(ast, a_node, "issue_effects")) |ie_node| {
        var buffer: [2]Ast.Node.Index = undefined;
        const array = ast.fullArrayInit(&buffer, ie_node) orelse return;

        if (self.ie_pk == common.STARTING_IE_PK) try self.issue_effects.append(self.allocator, '\n');

        for (array.ast.elements) |eff_node| {
            const eff_loc = common.getNodeLocation(ast, eff_node);
            const issue_node = common.findField(ast, eff_node, "issue") orelse blk: {
                try self.collector.reportMissingField(eff_loc, "issue effect", "issue");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };
            const score_node = common.findField(ast, eff_node, "score") orelse blk: {
                try self.collector.reportMissingField(eff_loc, "issue effect", "score");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };
            const importance_node = common.findField(ast, eff_node, "importance") orelse blk: {
                try self.collector.reportMissingField(eff_loc, "issue effect", "importance");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };

            const issue_id = try self.resolveId(ast, issue_node, .issues);
            const raw_score = common.getNodeSource(ast, score_node);
            const score_loc = common.getNodeLocation(ast, score_node);
            const importance_loc = common.getNodeLocation(ast, importance_node);
            const float_score = std.fmt.parseFloat(f64, raw_score) catch blk: {
                if (score_node == @as(Ast.Node.Index, @enumFromInt(0)))
                    break :blk @as(f64, 0.0);
                try self.collector.reportFieldTypeMismatch(score_loc, raw_score.len, "issue effect", "score", "float");
                break :blk 0.0;
            };
            const raw_importance = common.getNodeSource(ast, importance_node);
            const float_importance = std.fmt.parseFloat(f64, raw_importance) catch blk: {
                if (importance_node == @as(Ast.Node.Index, @enumFromInt(0)))
                    break :blk @as(f64, 0.0);
                try self.collector.reportFieldTypeMismatch(importance_loc, raw_score.len, "issue effect", "importance", "float");
                break :blk 0.0;
            };

            try self.issue_effects.print(self.allocator,
                \\  {{
                \\    model: "campaign_trail.candidate_issue_score",
                \\    pk: {d},
                \\    fields: {{
                \\      answer: {d},
                \\      issue: {d},
                \\      issue_score: {d},
                \\      issue_importance: {d},
                \\    }},
                \\  }},
                \\
            , .{ self.ie_pk, a_id, issue_id, float_score, float_importance });
        }
    }
}

pub fn resolveId(self: *Self, ast: *Ast, node: Ast.Node.Index, context: common.Context) !i32 {
    const tag: Ast.Node.Tag = ast.nodes.items(.tag)[@intFromEnum(node)];
    const tok: Ast.TokenIndex = ast.nodes.items(.main_token)[@intFromEnum(node)];
    const slice = ast.tokenSlice(tok);

    if (tag == .enum_literal) {
        const key = slice;
        var key_exists = false;

        const map = switch (context) {
            .candidates => &self.symbols.candidates,
            .states => &self.symbols.states,
            .issues => &self.symbols.issues,
        };

        if (map.contains(key)) return map.get(key).?;

        var other_map: ?common.Context = null;

        if (self.symbols.candidates.contains(key)) {
            other_map = .candidates;
            key_exists = true;
        }
        if (self.symbols.states.contains(key)) {
            other_map = .states;
            key_exists = true;
        }
        if (self.symbols.issues.contains(key)) {
            other_map = .issues;
            key_exists = true;
        }

        const period_tok = tok - 1;
        const period_loc = ast.tokenLocation(0, period_tok);

        const loc: common.Location = .{ .line = period_loc.line + 1, .column = period_loc.column + 1 };

        const tok_starts = ast.tokens.items(.start);
        const report_len = (tok_starts[tok] + slice.len) - tok_starts[period_tok];

        if (key_exists and other_map != null) {
            const msg = try std.fmt.allocPrint(self.allocator, "alias defined in .{s} used in field expecting alias defined in .{s}!", .{ @tagName(other_map.?), @tagName(context) });
            try self.collector.report(.@"error", .underline, loc, report_len, msg, null);
            return 0;
        }

        const err_msg = try std.fmt.allocPrint(self.allocator, "undefined alias used: '.{s}'", .{key});
        try self.collector.report(.@"error", .underline, loc, report_len, err_msg, null);

        if (self.symbols.findSuggestion(self.allocator, key, context)) |match| {
            const suggestion = try std.fmt.allocPrint(self.allocator, ".{s}", .{match});
            try self.collector.reportSuggestion(loc, report_len, suggestion);
        }

        return 0;
    }

    return std.fmt.parseInt(i32, slice, 10) catch 0;
}
