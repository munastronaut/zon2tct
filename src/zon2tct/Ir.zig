const std = @import("std");

const Ir = @This();

string_bytes: []u8,
payload: Payload,

pub const Payload = struct {
    questions: std.MultiArrayList(Question).Slice,
    answers: std.MultiArrayList(Answer).Slice,
    global_effects: std.MultiArrayList(GlobalEffect).Slice,
    state_effects: std.MultiArrayList(StateEffect).Slice,
    issue_effects: std.MultiArrayList(IssueEffect).Slice,

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
        effect: Effect,
    };
    pub const StateEffect = struct {
        pk: u32,
        state: u32,
        effect: Effect,
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
    empty = 0,
    _,
};

pub fn nullTerminatedString(ir: Ir, idx: NullTerminatedString) [:0]const u8 {
    const slice = ir.string_bytes[@intFromEnum(idx)..];
    return slice[0..std.mem.findScalar(u8, slice, 0).? :0];
}
