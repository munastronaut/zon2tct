const std = @import("std");

const Source = @import("../zon2tct.zig").Source;

pub const Message = struct {
    kind: Kind,
    text: []const u8,

    location: ?Source.ExpandedLocation = null,

    effective_kind: Kind = .off,

    pub const Kind = enum {
        off,
        note,
        warning,
        @"error",
        @"fatal error",
    };

    pub fn write(msg: Message, term: std.Io.Terminal, details: bool) std.Io.Terminal.SetColorError!void {
        const w = term.writer;
        try term.setColor(.bold);
        if (msg.location) |loc|
            try w.print("{s}:{d}:{d}: ", .{ loc.path, loc.line_no, loc.col });

        switch (msg.effective_kind) {
            .@"fatal error", .@"error" => try term.setColor(.bright_red),
            .note => try term.setColor(.bright_cyan),
            .warning => try term.setColor(.bright_magenta),
            .off => unreachable,
        }
        try w.print("{s}: ", .{@tagName(msg.effective_kind)});

        try term.setColor(.reset);
        try term.setColor(.bold);
        try w.writeAll(msg.text);

        if (!details or msg.location == null) {
            try w.writeByte('\n');
            try term.setColor(.reset);
        } else {
            const loc = msg.location.?;
            try term.setColor(.reset);
            try w.print("\n{s}\n", .{loc.line});
            try w.splatByteAll(' ', loc.width);
            try term.setColor(.bold);
            try term.setColor(.bright_green);
            try w.writeAll("^\n");
            try term.setColor(.reset);
        }
        try w.flush();
    }
};

const Diagnostics = @This();

output: union(enum) {
    to_writer: std.Io.Terminal,
    to_list: struct {
        messages: std.ArrayList(Message) = .empty,
        arena: std.heap.ArenaAllocator,
    },
    ignore,
},
color: ?bool = null,
details: bool = true,
errors: u32 = 0,
warnings: u32 = 0,
total: u32 = 0,
hide_notes: bool = false,

pub fn effectiveKind(d: *Diagnostics, message: anytype) Message.Kind {
    if (d.hide_notes and message.kind == .note) return .off;

    return message.kind;
}

pub fn add(d: *Diagnostics, msg: Message) error{ FatalError, OutOfMemory }!void {
    var copy = msg;
    copy.effective_kind = d.effectiveKind(msg);
    if (copy.effective_kind == .off) return;
    try d.addMessage(copy);
    if (copy.effective_kind == .@"fatal error") return error.FatalError;
}

pub fn formatArgs(w: *std.Io.Writer, fmt: []const u8, args: anytype) std.Io.Writer.Error!void {
    var i: usize = 0;
    inline for (std.meta.fields(@TypeOf(args))) |arg_info| {
        const arg = @field(args, arg_info.name);
        i += switch (@TypeOf(arg)) {
            []const u8 => try formatString(w, fmt[i..], arg),
            else => switch (@typeInfo(@TypeOf(arg))) {
                .int, .comptime_int => try Diagnostics.formatInt(w, fmt[i..], arg),
                .pointer => try Diagnostics.formatString(w, fmt[i..], arg),
                else => comptime unreachable,
            },
        };
    }
    try w.writeAll(fmt[i..]);
}

pub fn templateIndex(w: *std.Io.Writer, fmt: []const u8, template: []const u8) std.Io.Writer.Error!usize {
    const i = std.mem.indexOf(u8, fmt, template) orelse {
        if (@import("builtin").mode == .Debug)
            std.debug.panic("template `{s}` not found in format string `{s}`", .{ template, fmt });

        try w.print("template `{s}` not found in format string `{s}` (this is a bug)", .{ template, fmt });
        return 0;
    };
    try w.writeAll(fmt[0..i]);
    return i + template.len;
}

pub fn formatString(w: *std.Io.Writer, fmt: []const u8, str: []const u8) std.Io.Writer.Error!usize {
    const i = templateIndex(w, fmt, "{s}");
    try w.writeAll(str);
    return i;
}

pub fn formatInt(w: *std.Io.Writer, fmt: []const u8, int: anytype) std.Io.Writer.Error!usize {
    const i = templateIndex(w, fmt, "{d}");
    try w.printInt(int, 10, .lower, .{});
    return i;
}

fn addMessage(d: *Diagnostics, msg: Message) error{ FatalError, OutOfMemory }!void {
    std.debug.assert(msg.effective_kind != .off);
    switch (msg.effective_kind) {
        .off => unreachable,
        .@"error", .@"fatal error" => d.errors += 1,
        .warning => d.warnings += 1,
        .note => {},
    }
    d.total += 1;
    d.hide_notes = false;

    switch (d.output) {
        .ignore => {},
        .to_writer => |term| {
            var mode = term.mode;
            if (d.color == false) mode = .no_color;
            if (d.color == true and mode == .no_color) mode = .escape_codes;
            msg.write(.{
                .mode = mode,
                .writer = term.writer,
            }, d.details) catch return error.FatalError;
        },
        .to_list => |*list| {
            const arena = list.arena.allocator();
            try list.messages.append(list.arena.child_allocator, .{
                .kind = msg.kind,
                .effective_kind = msg.effective_kind,
                .text = try arena.dupe(u8, msg.text),
                .location = msg.location,
            });
        },
    }
}
