const Ir = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const zon2tct = @import("../zon2tct.zig");
const Tree = zon2tct.Tree;

string_bytes: []u8,
player: Player,
payload: Payload,

compile_errors: []CompileError,
error_notes: []CompileError.Note,

pub const Player = union(enum) {
    /// A `u32` pk was provided.
    pk: u32,
    /// A `u32` pk was not provided.
    /// In that case, the emitter should fall back to the variable `e.candidate_id`.
    default,

    pub fn format(p: Player, w: *Writer) Writer.Error!void {
        return switch (p) {
            .pk => |pk| w.printInt(pk, 10, .lower, .{}),
            .default => w.writeAll("e.candidate_id"),
        };
    }
};

pub const Payload = struct {
    symbols: []Symbol,
    questions: []Question,
    answers: []Answer,
    feedbacks: []Feedback,
    global_effects: []Effect,
    state_effects: []StateEffect,
    issue_effects: []IssueEffect,

    pub fn deinit(payload: *Payload, gpa: Allocator) void {
        gpa.free(payload.symbols);
        gpa.free(payload.questions);
        gpa.free(payload.answers);
        gpa.free(payload.feedbacks);
        gpa.free(payload.global_effects);
        gpa.free(payload.state_effects);
        gpa.free(payload.issue_effects);
        payload.* = undefined;
    }

    pub const Wip = struct {
        symbols: std.ArrayList(Symbol),
        questions: std.ArrayList(Question),
        answers: std.ArrayList(Answer),
        feedbacks: std.ArrayList(Feedback),
        global_effects: std.ArrayList(Effect),
        state_effects: std.ArrayList(StateEffect),
        issue_effects: std.ArrayList(IssueEffect),

        pub fn deinit(wip: *Wip, gpa: Allocator) void {
            wip.symbols.deinit(gpa);
            wip.questions.deinit(gpa);
            wip.answers.deinit(gpa);
            wip.feedbacks.deinit(gpa);
            wip.global_effects.deinit(gpa);
            wip.state_effects.deinit(gpa);
            wip.issue_effects.deinit(gpa);
            wip.* = undefined;
        }

        pub fn toOwnedPayload(wip: *Wip, gpa: Allocator) Allocator.Error!Payload {
            return .{
                .symbols = try wip.symbols.toOwnedSlice(gpa),
                .questions = try wip.questions.toOwnedSlice(gpa),
                .answers = try wip.answers.toOwnedSlice(gpa),
                .feedbacks = try wip.feedbacks.toOwnedSlice(gpa),
                .global_effects = try wip.global_effects.toOwnedSlice(gpa),
                .state_effects = try wip.state_effects.toOwnedSlice(gpa),
                .issue_effects = try wip.issue_effects.toOwnedSlice(gpa),
            };
        }
    };

    pub const Symbol = struct {
        kind: enum { question, answer },
        idx: u32,
        name: NullTerminatedString,
    };

    pub const Question = struct {
        text: NullTerminatedString,
    };

    pub const Answer = struct {
        qn: u32,
        text: NullTerminatedString,
    };

    pub const Feedback = struct {
        ans: u32,
        text: NullTerminatedString,
    };

    pub const Effect = struct {
        ans: u32,
        tgt: u32,
        mult: Number,
    };

    pub const StateEffect = struct {
        state: u32,
        eff: Effect,
    };

    pub const IssueEffect = struct {
        ans: u32,
        issue: u32,
        score: Number,
        impt: Number,
        tgt: TgtUnion,

        pub const TgtUnion = union(enum) {
            cand: ?u32,
            state: u32,

            pub fn format(u: TgtUnion, w: *Writer) Writer.Error!void {
                switch (u) {
                    .cand => |cand| if (cand) |pk| {
                        try w.print(
                            \\
                            \\      tag: "CANDIDATE",
                            \\      candidate: {d},
                        , .{pk});
                    },
                    .state => |pk| try w.print(
                        \\
                        \\      tag: "STATE",
                        \\      state: {d},
                    , .{pk}),
                }
            }
        };
    };
};

pub fn hasCompileErrors(ir: Ir) bool {
    if (ir.compile_errors.len > 0) {
        return true;
    } else {
        assert(ir.error_notes.len == 0);
        return false;
    }
}

pub fn deinit(ir: *Ir, gpa: Allocator) void {
    ir.payload.deinit(gpa);
    gpa.free(ir.string_bytes);
    gpa.free(ir.compile_errors);
    gpa.free(ir.error_notes);
    ir.* = undefined;
}

pub const NullTerminatedString = enum(u32) {
    empty = 0,
    _,
    pub fn get(nts: NullTerminatedString, ir: Ir) [:0]const u8 {
        return nts.getAny(ir.string_bytes);
    }
    pub fn getAny(nts: NullTerminatedString, string_bytes: []u8) [:0]const u8 {
        const idx = std.mem.findScalar(u8, string_bytes[@backingInt(nts)..], 0).?;
        return string_bytes[@backingInt(nts)..][0..idx :0];
    }
};

pub const Number = enum(u64) {
    _,

    pub fn format(num: Number, w: *Writer) Writer.Error!void {
        const val: f64 = @bitCast(@backingInt(num));
        if (std.math.isFinite(val)) return w.print("{d}", .{val});
        if (std.math.isInf(val)) {
            if (std.math.sign(val) == -1) try w.writeByte('-');
            return w.writeAll("Infinity");
        }
        return w.writeAll("NaN");
    }

    pub fn fromFloat(num: f64) Number {
        return @fromBackingInt(@bitCast(num));
    }

    test format {
        try testFormat("5", 5.0);
        try testFormat("1.618033988749895", std.math.phi);
        try testFormat("Infinity", std.math.inf(f64));
        try testFormat("-Infinity", -std.math.inf(f64));
        try testFormat("NaN", std.math.nan(f64));
        try testFormat("NaN", -std.math.nan(f64));
    }

    fn testFormat(expected: []const u8, input: f64) !void {
        var aw: Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try aw.writer.print("{f}", .{Number.fromFloat(input)});
        return std.testing.expectEqualStrings(expected, aw.written());
    }
};

pub const CompileError = extern struct {
    msg: NullTerminatedString,
    token: Tree.OptionalTokenIndex,
    node_or_offset: u32,
    first_note: u32,
    note_count: u32,

    pub fn getNotes(err: CompileError, ir: Ir) []const Note {
        return ir.error_notes[err.first_note..][0..err.note_count];
    }

    pub const Note = extern struct {
        msg: NullTerminatedString,
        token: Tree.OptionalTokenIndex,
        node_or_offset: u32,
    };
};

test {
    _ = Number;
}
