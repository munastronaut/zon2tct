const Ir = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Tree = @import("Tree.zig");

extra: []u32,
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

    pub fn format(p: Player, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (p) {
            .pk => |pk| w.printInt(pk, 10, .lower, .{}),
            .default => w.writeAll("e.candidate_id"),
        };
    }
};

pub const Payload = struct {
    questions: std.ArrayList(Question),
    answers: std.ArrayList(Answer),
    global_effects: std.ArrayList(GlobalEffect),
    state_effects: std.ArrayList(StateEffect),
    issue_effects: std.ArrayList(IssueEffect),

    pub fn deinit(p: *Payload, gpa: Allocator) void {
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

pub fn hasCompileErrors(ir: Ir) bool {
    if (ir.compile_errors.len > 0) {
        assert(ir.extra.len == 0);
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
    _,
    pub fn get(nts: NullTerminatedString, ir: Ir) [:0]const u8 {
        const idx = std.mem.findScalar(u8, ir.string_bytes[@intFromEnum(nts)..], 0).?;
        return ir.string_bytes[@intFromEnum(nts)..][0..idx :0];
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
