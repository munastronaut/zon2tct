const Emit = @This();

const zon2tct = @import("zon2tct");
const Ir = zon2tct.Ir;

const std = @import("std");
const Writer = std.Io.Writer;

w: *Writer,
ir: Ir,

const Base = struct {
    qn: usize,
    ans: usize,
    fdbk: usize,
    geff: usize,
    seff: usize,
    ieff: usize,

    pub fn init(payload: Ir.Payload, qn: usize) Base {
        const ans = qn + payload.questions.len;
        const fdbk = ans + payload.answers.len;
        const geff = fdbk + payload.feedbacks.len;
        const seff = geff + payload.global_effects.len;
        const ieff = seff + payload.state_effects.len;

        return .{
            .qn = qn,
            .ans = ans,
            .fdbk = fdbk,
            .geff = geff,
            .seff = seff,
            .ieff = ieff,
        };
    }
};

pub fn emit(e: *Emit) !void {
    const w = e.w;
    const ir = e.ir;
    const payload = ir.payload;

    const base: Base = .init(payload, 1000);

    if (payload.symbols.len > 0) {
        try w.writeAll("const SYMBOLS = {");
        for (payload.symbols, 0..) |symbol, i| {
            const key = symbol.name.get(ir);
            const pk = switch (symbol.kind) {
                .question => base.qn + symbol.idx,
                .answer => base.ans + symbol.idx,
            };

            if (i == 0) try w.writeByte('\n');
            if (zon2tct.isValidId(key)) {
                try w.print("  {s}: {d},\n", .{ key, pk });
            } else {
                try w.print("  \"{s}\": {d},\n", .{ key, pk });
            }
        }
        try w.writeAll("};\n\n");
    }

    try w.writeAll("e ||= campaignTrail_temp;\n\n");

    if (payload.questions.len > 0) {
        try w.writeAll("e.questions_json = [");
        for (payload.questions, 0..) |question, i| {
            if (i == 0) try w.writeByte('\n');
            try w.print(
                \\  {{
                \\    model: "campaign_trail.question",
                \\    pk: {d},
                \\    fields: {{
                \\      priority: 1,
                \\      description: "{f}",
                \\      likelihood: 1,
                \\    }}
                \\  }},
                \\
            , .{ base.qn + i, zon2tct.fmtString(question.text.get(ir)) });
        }
        try w.writeAll("];\n\n");
    }

    if (payload.answers.len > 0) {
        try w.writeAll("e.answers_json = [");
        for (payload.answers, 0..) |answer, i| {
            if (i == 0) try w.writeByte('\n');
            try w.print(
                \\  {{
                \\    model: "campaign_trail.answer",
                \\    pk: {d},
                \\    fields: {{
                \\      question: {d},
                \\      description: "{f}",
                \\    }}
                \\  }},
                \\
            , .{
                base.ans + i,
                base.qn + answer.qn,
                zon2tct.fmtString(answer.text.get(ir)),
            });
        }
        try w.writeAll("];\n\n");
    }

    if (payload.feedbacks.len > 0) {
        try w.writeAll("e.answer_feedback_json = [");
        for (payload.feedbacks, 0..) |feedback, i| {
            if (i == 0) try w.writeByte('\n');
            try w.print(
                \\  {{
                \\    model: "campaign_trail.answer_feedback",
                \\    pk: {d},
                \\    fields: {{
                \\      answer: {d},
                \\      candidate: {f},
                \\      answer_feedback: "{f}",
                \\    }}
                \\  }},
                \\
            , .{
                base.fdbk + i,
                base.ans + feedback.ans,
                ir.player,
                zon2tct.fmtString(feedback.text.get(ir)),
            });
        }
        try w.writeAll("];\n\n");
    }

    if (payload.global_effects.len > 0) {
        try w.writeAll("e.answer_score_global_json = [");
        for (payload.global_effects, 0..) |geff, i| {
            if (i == 0) try w.writeByte('\n');
            try w.print(
                \\  {{
                \\    model: "campaign_trail.answer_score_global",
                \\    pk: {d},
                \\    fields: {{
                \\      answer: {d},
                \\      candidate: {f},
                \\      affected_candidate: {d},
                \\      global_multiplier: {f},
                \\    }}
                \\  }},
                \\
            , .{
                base.geff + i,
                base.ans + geff.ans,
                ir.player,
                geff.tgt,
                geff.mult,
            });
        }
        try w.writeAll("];\n\n");
    }

    if (payload.state_effects.len > 0) {
        try w.writeAll("e.answer_score_state_json = [");
        for (payload.state_effects, 0..) |seff, i| {
            if (i == 0) try w.writeByte('\n');
            try w.print(
                \\  {{
                \\    model: "campaign_trail.answer_score_state",
                \\    pk: {d},
                \\    fields: {{
                \\      answer: {d},
                \\      state: {d},
                \\      candidate: {f},
                \\      affected_candidate: {d},
                \\      state_multiplier: {f},
                \\    }}
                \\  }},
                \\
            , .{
                base.seff + i,
                base.ans + seff.eff.ans,
                seff.state,
                ir.player,
                seff.eff.tgt,
                seff.eff.mult,
            });
        }
        try w.writeAll("];\n\n");
    }

    if (payload.issue_effects.len > 0) {
        try w.writeAll("e.answer_score_issue_json = [");
        for (payload.issue_effects, 0..) |ieff, i| {
            if (i == 0) try w.writeByte('\n');
            try w.print(
                \\  {{
                \\    model: "campaign_trail.candidate_issue_score",
                \\    pk: {d},
                \\    fields: {{{f}
                \\      answer: {d},
                \\      issue: {d},
                \\      issue_score: {f},
                \\      issue_importance: {f},
                \\    }}
                \\  }},
                \\
            , .{
                base.ieff + i,
                ieff.tgt,
                base.ans + ieff.ans,
                ieff.issue,
                ieff.score,
                ieff.impt,
            });
        }
        try w.writeAll("];\n\n");
    }

    return w.flush();
}
