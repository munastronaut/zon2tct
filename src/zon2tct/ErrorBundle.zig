const ErrorBundle = @This();

const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;

const zon2tct = @import("../zon2tct.zig");
const Color = zon2tct.Color;

string_bytes: []const u8,
extra: []const u32,

pub const String = u32;
pub const OptionalString = u32;

pub const empty: ErrorBundle = .{
    .string_bytes = &.{},
    .extra = &.{},
};

pub const MessageIndex = enum(u32) {
    _,
};

pub const SourceLocationIndex = enum(u32) {
    none = 0,
    _,
};

pub const ErrorMessageList = struct {
    len: u32,
    start: u32,
};

pub const SourceLocation = struct {
    src_path: String,
    line: u32,
    column: u32,
    span_start: u32,
    span_main: u32,
    span_end: u32,
    src_line: OptionalString = 0,
};

pub const ErrorMessage = struct {
    msg: String,
    count: u32 = 1,
    src_loc: SourceLocationIndex = .none,
    notes_len: u32 = 0,
};

pub fn deinit(eb: *ErrorBundle, gpa: Allocator) void {
    gpa.free(eb.string_bytes);
    gpa.free(eb.extra);
    eb.* = undefined;
}

pub fn getErrorMessageList(eb: ErrorBundle) ErrorMessageList {
    return eb.extraData(ErrorMessageList, 0).data;
}

pub fn getMessages(eb: ErrorBundle) []const MessageIndex {
    const list = eb.getErrorMessageList();
    return @as([]const MessageIndex, @ptrCast(eb.extra[list.start..][0..list.len]));
}

pub fn getErrorMessage(eb: ErrorBundle, index: MessageIndex) ErrorMessage {
    return eb.extraData(ErrorMessage, @backingInt(index)).data;
}

pub fn getNotes(eb: ErrorBundle, index: MessageIndex) []const MessageIndex {
    const notes_len = eb.getErrorMessage(index).notes_len;
    const start = @backingInt(index) + @typeInfo(ErrorMessage).@"struct".field_names.len;
    return @as([]const MessageIndex, @ptrCast(eb.extra[start..][0..notes_len]));
}

fn extraData(eb: ErrorBundle, comptime T: type, index: usize) struct { data: T, end: usize } {
    const info = @typeInfo(T);
    const field_names = info.@"struct".field_names;
    const field_types = info.@"struct".field_types;
    var i: usize = index;
    var result: T = undefined;
    inline for (field_names, field_types) |field_name, field_type| {
        @field(result, field_name) = switch (field_type) {
            u32 => eb.extra[i],
            MessageIndex => @as(MessageIndex, @fromBackingInt(eb.extra[i])),
            SourceLocationIndex => @as(SourceLocationIndex, @fromBackingInt(eb.extra[i])),
            else => @compileError("bad field type"),
        };
        i += 1;
    }
    return .{
        .data = result,
        .end = i,
    };
}

pub fn nullTerminatedString(eb: ErrorBundle, index: String) [:0]const u8 {
    const string_bytes = eb.string_bytes;
    const end = std.mem.findScalar(u8, string_bytes[index..], 0).?;
    return string_bytes[index..][0..end :0];
}

pub fn renderToStderr(eb: ErrorBundle, io: Io, color: Color) (Io.Cancelable || Io.File.Writer.Error)!void {
    var buf: [256]u8 = undefined;
    const stderr = try io.lockStderr(&buf, color.terminalMode());
    defer io.unlockStderr();
    eb.renderToTerminal(stderr.terminal()) catch |err| switch (err) {
        error.WriteFailed => return stderr.file_writer.err.?,
        else => |e| return e,
    };
}

pub fn renderToTerminal(eb: ErrorBundle, t: Io.Terminal) Io.Terminal.SetColorError!void {
    if (eb.extra.len == 0) return;
    for (eb.getMessages()) |err_msg| {
        try eb.renderErrorMessage(err_msg, t, "error", .red, 0);
    }
}

fn renderErrorMessage(
    eb: ErrorBundle,
    err_msg_idx: MessageIndex,
    t: Io.Terminal,
    kind: []const u8,
    color: Io.Terminal.Color,
    indent: usize,
) Io.Terminal.SetColorError!void {
    const w = t.writer;
    const err_msg = eb.getErrorMessage(err_msg_idx);
    if (err_msg.src_loc != .none) {
        const src = eb.extraData(SourceLocation, @backingInt(err_msg.src_loc));
        var prefix: Writer.Discarding = .init(&.{});
        var pw = prefix.writer;
        try w.splatByteAll(' ', indent);
        prefix.count += indent;
        try t.setColor(.bold);
        try w.print("{s}:{d}:{d}: ", .{
            eb.nullTerminatedString(src.data.src_path),
            src.data.line + 1,
            src.data.column + 1,
        });
        try pw.print("{s}:{d}:{d}: ", .{
            eb.nullTerminatedString(src.data.src_path),
            src.data.line + 1,
            src.data.column + 1,
        });
        try t.setColor(color);
        try w.writeAll(kind);
        prefix.count += kind.len;
        try w.writeAll(": ");
        prefix.count += 2;
        const prefix_len: usize = @intCast(prefix.count);
        try t.setColor(.reset);
        try t.setColor(.bold);
        if (err_msg.count == 1) {
            try eb.writeMsg(err_msg, w, prefix_len);
            try w.writeByte('\n');
        } else {
            try eb.writeMsg(err_msg, w, prefix_len);
            try t.setColor(.dim);
            try w.print(" ({d} times)\n", .{err_msg.count});
        }
        try t.setColor(.reset);
        if (src.data.src_line != 0) {
            try w.splatByteAll(' ', indent);
            const line = eb.nullTerminatedString(src.data.src_line);
            for (line) |b| switch (b) {
                '\t' => try w.writeByte(' '),
                else => try w.writeByte(b),
            };
            try w.writeByte('\n');
            try w.splatByteAll(' ', indent);
            const before_caret = src.data.span_main - src.data.span_start;
            const after_caret = src.data.span_end -| src.data.span_main -| 1;
            try w.splatByteAll(' ', src.data.column - before_caret);
            try t.setColor(.green);
            try w.splatByteAll('~', before_caret);
            try w.writeByte('^');
            try w.splatByteAll('~', after_caret);
            try w.writeByte('\n');
            try t.setColor(.reset);
        }
        for (eb.getNotes(err_msg_idx)) |note| {
            try eb.renderErrorMessage(note, t, "note", .cyan, indent);
        }
    } else {
        try t.setColor(color);
        try w.splatByteAll(' ', indent);
        try w.writeAll(kind);
        try w.writeAll(": ");
        try t.setColor(.reset);
        const msg = eb.nullTerminatedString(err_msg.msg);
        if (err_msg.count == 1) {
            try w.print("{s}\n", .{msg});
        } else {
            try w.print("{s}", .{msg});
            try t.setColor(.dim);
            try w.print(" ({d} times)\n", .{err_msg.count});
        }
        try t.setColor(.reset);
        for (eb.getNotes(err_msg_idx)) |note| {
            try eb.renderErrorMessage(note, t, "note", .cyan, indent + 4);
        }
    }
}

fn writeMsg(eb: ErrorBundle, err_msg: ErrorMessage, w: *Writer, indent: usize) !void {
    var lines = mem.splitScalar(u8, eb.nullTerminatedString(err_msg.msg), '\n');
    while (lines.next()) |line| {
        try w.writeAll(line);
        if (lines.index == null) break;
        try w.writeByte('\n');
        try w.splatByteAll(' ', indent);
    }
}

pub const Wip = struct {
    gpa: Allocator,
    string_bytes: std.ArrayList(u8),
    extra: std.ArrayList(u32),
    root_list: std.ArrayList(MessageIndex),

    pub fn init(wip: *Wip, gpa: Allocator) !void {
        wip.* = .{
            .gpa = gpa,
            .string_bytes = .empty,
            .extra = .empty,
            .root_list = .empty,
        };

        try wip.string_bytes.append(gpa, 0);

        assert(0 == try wip.addExtra(ErrorMessageList{
            .len = 0,
            .start = 0,
        }));
    }

    pub fn deinit(wip: *Wip) void {
        const gpa = wip.gpa;
        wip.string_bytes.deinit(gpa);
        wip.extra.deinit(gpa);
        wip.root_list.deinit(gpa);
        wip.* = undefined;
    }

    pub fn toOwnedBundle(wip: *Wip) !ErrorBundle {
        const gpa = wip.gpa;
        if (wip.root_list.items.len == 0) {
            wip.deinit();
            wip.* = .{
                .gpa = gpa,
                .string_bytes = .empty,
                .extra = .empty,
                .root_list = .empty,
            };
            return empty;
        }

        wip.setExtra(0, ErrorMessageList{
            .len = @intCast(wip.root_list.items.len),
            .start = @intCast(wip.extra.items.len),
        });
        try wip.extra.appendSlice(gpa, @as([]const u32, @ptrCast(wip.root_list.items)));
        wip.root_list.clearAndFree(gpa);
        return .{
            .string_bytes = try wip.string_bytes.toOwnedSlice(gpa),
            .extra = try wip.extra.toOwnedSlice(gpa),
        };
    }

    pub fn addString(wip: *Wip, s: []const u8) Allocator.Error!String {
        const gpa = wip.gpa;
        const index: String = @intCast(wip.string_bytes.items.len);
        try wip.string_bytes.ensureUnusedCapacity(gpa, s.len + 1);
        wip.string_bytes.appendSliceAssumeCapacity(s);
        wip.string_bytes.appendAssumeCapacity(0);
        return index;
    }

    pub fn addRootErrorMessage(wip: *Wip, em: ErrorMessage) Allocator.Error!void {
        try wip.root_list.ensureUnusedCapacity(wip.gpa, 1);
        wip.root_list.appendAssumeCapacity(try wip.addErrorMessage(em));
    }

    pub fn addErrorMessage(wip: *Wip, em: ErrorMessage) Allocator.Error!MessageIndex {
        return @fromBackingInt(try wip.addExtra(em));
    }

    pub fn addErrorMessageAssumeCapacity(wip: *Wip, em: ErrorMessage) MessageIndex {
        return @fromBackingInt(wip.addExtraAssumeCapacity(em));
    }

    pub fn addSourceLocation(wip: *Wip, sl: SourceLocation) Allocator.Error!SourceLocationIndex {
        return @fromBackingInt(try wip.addExtra(sl));
    }

    pub fn reserveNotes(wip: *Wip, notes_len: u32) !u32 {
        try wip.extra.ensureUnusedCapacity(wip.gpa, notes_len +
            notes_len * @typeInfo(ErrorBundle.ErrorMessage).@"struct".field_names.len);
        wip.extra.items.len += notes_len;
        return @intCast(wip.extra.items.len - notes_len);
    }

    pub fn addIrErrorMessages(
        eb: *Wip,
        ir: zon2tct.Ir,
        tree: zon2tct.Tree,
        src: [:0]const u8,
        src_path: []const u8,
    ) !void {
        assert(ir.hasCompileErrors());

        for (ir.compile_errors) |err| {
            const err_span: zon2tct.Tree.Span = span: {
                if (err.token.unwrap()) |tok| {
                    const tok_start = tree.tokenStart(tok);
                    const start = tok_start + err.node_or_offset;
                    const end = tok_start + @as(u32, @intCast(tree.tokenSlice(tok).len));
                    break :span .{ .start = start, .end = end, .main = start };
                } else {
                    break :span tree.nodeToSpan(@fromBackingInt(err.node_or_offset));
                }
            };
            const err_loc = zon2tct.findLineColumn(src, err_span.main);

            try eb.addRootErrorMessage(.{
                .msg = try eb.addString(err.msg.get(ir)),
                .src_loc = try eb.addSourceLocation(.{
                    .src_path = try eb.addString(src_path),
                    .span_start = err_span.start,
                    .span_main = err_span.main,
                    .span_end = err_span.end,
                    .line = @intCast(err_loc.line),
                    .column = @intCast(err_loc.column),
                    .src_line = try eb.addString(err_loc.source_line),
                }),
                .notes_len = err.note_count,
            });

            const notes_start = try eb.reserveNotes(err.note_count);
            for (notes_start.., err.first_note.., 0..err.note_count) |eb_note_idx, ir_note_idx, _| {
                const note = ir.error_notes[ir_note_idx];
                const note_span: zon2tct.Tree.Span = span: {
                    if (note.token.unwrap()) |tok| {
                        const tok_start = tree.tokenStart(tok);
                        const start = tok_start + note.node_or_offset;
                        const end = tok_start + @as(u32, @intCast(tree.tokenSlice(tok).len));
                        break :span .{ .start = start, .end = end, .main = start };
                    } else {
                        break :span tree.nodeToSpan(@fromBackingInt(note.node_or_offset));
                    }
                };
                const note_loc = zon2tct.findLineColumn(src, note_span.main);

                const note_idx = @backingInt(try eb.addErrorMessage(.{
                    .msg = try eb.addString(note.msg.get(ir)),
                    .src_loc = try eb.addSourceLocation(.{
                        .src_path = try eb.addString(src_path),
                        .span_start = note_span.start,
                        .span_main = note_span.main,
                        .span_end = note_span.end,
                        .line = @intCast(note_loc.line),
                        .column = @intCast(note_loc.column),
                        .src_line = if (note_loc.eql(err_loc))
                            0
                        else
                            try eb.addString(note_loc.source_line),
                    }),
                    .notes_len = 0,
                }));
                eb.extra.items[eb_note_idx] = note_idx;
            }
        }
    }

    fn addExtra(wip: *Wip, extra: anytype) Allocator.Error!u32 {
        const gpa = wip.gpa;
        const fields = @typeInfo(@TypeOf(extra)).@"struct".field_names;
        try wip.extra.ensureUnusedCapacity(gpa, fields.len);
        return wip.addExtraAssumeCapacity(extra);
    }

    fn addExtraAssumeCapacity(wip: *Wip, extra: anytype) u32 {
        const fields = @typeInfo(@TypeOf(extra)).@"struct".field_names;
        const result: u32 = @intCast(wip.extra.items.len);
        wip.extra.items.len += fields.len;
        wip.setExtra(result, extra);
        return result;
    }

    fn setExtra(wip: *Wip, index: usize, extra: anytype) void {
        const extra_info = @typeInfo(@TypeOf(extra)).@"struct";
        const field_names = extra_info.field_names;
        const field_types = extra_info.field_types;
        var i = index;
        inline for (field_names, field_types) |field_name, field_type| {
            wip.extra.items[i] = switch (field_type) {
                u32 => @field(extra, field_name),

                MessageIndex,
                SourceLocationIndex,
                => @backingInt(@field(extra, field_name)),

                else => @compileError("bad field type"),
            };
            i += 1;
        }
    }
};
