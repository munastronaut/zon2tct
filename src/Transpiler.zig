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

    const q_text_node = common.findField(ast, q_node, "text") orelse blk: {
        try self.collector.report(.@"error", common.getNodeLocation(ast, q_node), "question is missing required field 'text'");
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
        try self.collector.report(.@"error", common.getNodeLocation(ast, q_node), "question is missing required field 'answers'");
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

    const a_text_node = common.findField(ast, a_node, "text") orelse blk: {
        try self.collector.report(.@"error", common.getNodeLocation(ast, a_node), "answer is missing required field 'text'");
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
            const target_node = common.findField(ast, eff_node, "target") orelse blk: {
                try self.collector.report(.@"error", common.getNodeLocation(ast, eff_node), "global effect is missing required field 'target'");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };
            const effect_node = common.findField(ast, eff_node, "effect") orelse blk: {
                try self.collector.report(.@"error", common.getNodeLocation(ast, eff_node), "global effect is missing required field 'effect'");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };

            const target_id = try self.resolveId(ast, target_node);
            const raw_effect = common.getNodeSource(ast, effect_node);

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

    if (common.findField(ast, a_node, "state_effects")) |se_node| {
        var buffer: [2]Ast.Node.Index = undefined;
        const array = ast.fullArrayInit(&buffer, se_node) orelse return;

        if (self.se_pk == common.STARTING_SE_PK) try self.state_effects.append(self.allocator, '\n');

        for (array.ast.elements) |eff_node| {
            const state_node = common.findField(ast, eff_node, "state") orelse continue;
            const state_id = try self.resolveId(ast, state_node);

            var buf: [2]Ast.Node.Index = undefined;
            const effects_node = common.findField(ast, eff_node, "effects") orelse continue;
            const eff_arr = ast.fullArrayInit(&buf, effects_node) orelse return;

            for (eff_arr.ast.elements) |sef_node| {
                const target_node = common.findField(ast, sef_node, "target") orelse blk: {
                    try self.collector.report(.@"error", common.getNodeLocation(ast, sef_node), "state effect is missing required field 'target'");
                    break :blk @as(Ast.Node.Index, @enumFromInt(0));
                };
                const effect_node = common.findField(ast, sef_node, "effect") orelse blk: {
                    try self.collector.report(.@"error", common.getNodeLocation(ast, sef_node), "state effect is missing required field 'effect'");
                    break :blk @as(Ast.Node.Index, @enumFromInt(0));
                };

                const target_id = try self.resolveId(ast, target_node);
                const raw_effect = common.getNodeSource(ast, effect_node);

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

    if (common.findField(ast, a_node, "issue_effects")) |ie_node| {
        var buffer: [2]Ast.Node.Index = undefined;
        const array = ast.fullArrayInit(&buffer, ie_node) orelse return;

        if (self.ie_pk == common.STARTING_IE_PK) try self.issue_effects.append(self.allocator, '\n');

        for (array.ast.elements) |eff_node| {
            const issue_node = common.findField(ast, eff_node, "issue") orelse blk: {
                try self.collector.report(.@"error", common.getNodeLocation(ast, eff_node), "issue effect is missing required field 'issue'");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };
            const score_node = common.findField(ast, eff_node, "score") orelse blk: {
                try self.collector.report(.@"error", common.getNodeLocation(ast, eff_node), "issue effect is missing required field 'score'");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };
            const importance_node = common.findField(ast, eff_node, "importance") orelse blk: {
                try self.collector.report(.@"error", common.getNodeLocation(ast, eff_node), "issue effect is missing required field 'importance'");
                break :blk @as(Ast.Node.Index, @enumFromInt(0));
            };

            const issue_id = try self.resolveId(ast, issue_node);
            const raw_effect = common.getNodeSource(ast, score_node);
            const raw_importance = common.getNodeSource(ast, importance_node);

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

pub fn resolveId(self: *Self, ast: *Ast, node: Ast.Node.Index) !i32 {
    const tag: Ast.Node.Tag = ast.nodes.items(.tag)[@intFromEnum(node)];
    const tok: Ast.TokenIndex = ast.nodes.items(.main_token)[@intFromEnum(node)];
    const slice = ast.tokenSlice(tok);

    if (tag == .enum_literal) {
        const key = if (slice[0] == '.') slice[1..] else slice;

        if (self.symbols.candidates.get(key)) |val| return val;
        if (self.symbols.states.get(key)) |val| return val;
        if (self.symbols.issues.get(key)) |val| return val;

        try self.collector.report(.@"error", common.getNodeLocation(ast, node), try std.fmt.allocPrint(self.allocator, "undefined alias used: .{s}", .{key}));
        return 0;
    }

    return std.fmt.parseInt(i32, slice, 10) catch 0;
}
