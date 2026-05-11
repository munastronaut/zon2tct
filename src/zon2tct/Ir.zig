const Ir = @This();

const std = @import("std");

string_bytes: []u8,
payload: Payload,

pub const Payload = struct {
    questions: std.ArrayList(Question),
    answers: std.ArrayList(Answer),
    global_effects: std.ArrayList(GlobalEffect),
    state_effects: std.ArrayList(StateEffect),
    issue_effects: std.ArrayList(IssueEffect),

    pub fn deinit(p: *Payload, gpa: std.mem.Allocator) void {
        p.questions.deinit(gpa);
        p.answers.deinit(gpa);
        p.global_effects.deinit(gpa);
        p.state_effects.deinit(gpa);
        p.issue_effects.deinit(gpa);
    }

    pub const Question = struct {
        pk: u32,
        text: NullTerminatedString,
    };

    pub const Answer = struct {
        pk: u32,
        qn: u32,
        text: NullTerminatedString,
        fdbk: NullTerminatedString,
    };

    pub const Effect = struct {
        ans: u32,
        tgt: u32,
        mult: f64,
    };

    pub const GlobalEffect = struct {
        pk: u32,
        eff: Effect,
    };

    pub const StateEffect = struct {
        pk: u32,
        state: u32,
        eff: Effect,
    };

    pub const IssueEffect = struct {
        pk: u32,
        ans: u32,
        issue: u32,
        score: f64,
        impt: f64,
        tgt: union(enum) {
            cand: ?u32,
            state: u32,
        },
    };
};

pub fn deinit(ir: *Ir, gpa: std.mem.Allocator) void {
    ir.payload.deinit(gpa);
    gpa.free(ir.string_bytes);
    ir.* = undefined;
}

pub const NullTerminatedString = enum(u32) {
    _,
    pub fn get(nts: NullTerminatedString, ir: Ir) [:0]const u8 {
        const idx = std.mem.findScalar(u8, ir.string_bytes[@intFromEnum(nts)..], 0).?;
        return ir.string_bytes[@intFromEnum(nts)..][0..idx :0];
    }
};
