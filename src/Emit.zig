const Emit = @This();

const Compilation = @import("Compilation.zig");
const zon2tct = @import("zon2tct");

const std = @import("std");
const Writer = std.Io.Writer;

comp: *Compilation,
w: *Writer,
ir: zon2tct.Ir,

pub fn emit(e: *Emit) !void {
    const w = e.w;
    const ir = e.ir;
    const payload = ir.payload;

    const base_qn = 1000;
    const base_ans = base_qn + payload.questions.len;
    const base_fdbk = base_ans + payload.answers.len;
    const base_geff = base_fdbk + payload.feedbacks.len;
    const base_seff = base_geff + payload.global_effects.len;
    const base_ieff = base_seff + payload.state_effects.len;

    if (payload.symbols.len > 0) {
        try w.writeAll("const SYMBOLS = {");
        for (payload.symbols, 0..) |symbol, i| {
            const key = symbol.name.get(ir);
            const pk = switch (symbol.kind) {
                .question => base_qn + symbol.idx,
                .answer => base_ans + symbol.idx,
            };

            if (i == 0) try w.writeByte('\n');
            if (zon2tct.isValidId(key)) {
                try w.print(
                    \\  {s}: {d}
                , .{ key, pk });
            } else {
                try w.print(
                    \\  "{s}": {d}
                , .{ key, pk });
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
            , .{ base_qn + i, zon2tct.fmtString(question.text.get(ir)) });
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
                base_ans + i,
                base_qn + answer.qn,
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
                base_fdbk + i,
                base_ans + feedback.ans,
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
            , .{ base_geff + i, base_ans + geff.ans, ir.player, geff.tgt, geff.mult });
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
            , .{ base_seff + i, base_ans + seff.eff.ans, seff.state, ir.player, seff.eff.tgt, seff.eff.mult });
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
            , .{ base_ieff + i, ieff.tgt, base_ans + ieff.ans, ieff.issue, ieff.score, ieff.impt });
        }
        try w.writeAll("];\n\n");
    }

    return w.flush();
}
