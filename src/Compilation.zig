const Compilation = @This();

const Emit = @import("Emit.zig");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = mem.Allocator;
const fatal = std.process.fatal;

const zon2tct = @import("zon2tct");

gpa: Allocator,
arena: Allocator,
io: Io,

color: zon2tct.Color,
src_file: []const u8,
provided_name: ?[]const u8 = null,

pub const CreateOptions = struct {
    color: zon2tct.Color,
    src_file: []const u8,
    provided_name: ?[]const u8 = null,
};

pub const CreateError = Allocator.Error;

pub fn create(gpa: Allocator, arena: Allocator, io: Io, options: CreateOptions) CreateError!*Compilation {
    const comp = try arena.create(Compilation);

    comp.* = .{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .color = options.color,
        .src_file = options.src_file,
        .provided_name = options.provided_name,
    };

    return comp;
}

pub fn work(comp: *Compilation) !void {
    const gpa = comp.gpa;
    const io = comp.io;
    const src: [:0]const u8 = s: {
        var f = Io.Dir.cwd().openFile(io, comp.src_file, .{}) catch |err| {
            fatal("unable to open file '{s}': {t}", .{ comp.src_file, err });
        };
        defer f.close(io);
        var read_buf: [1024]u8 = undefined;
        var file_reader = f.reader(io, &read_buf);
        break :s zon2tct.readSourceFileToEndAlloc(gpa, &file_reader) catch |err| {
            fatal("unable to load file '{s}': {t}", .{ comp.src_file, err });
        };
    };
    defer gpa.free(src);

    var tree: zon2tct.Tree = try .parse(gpa, src);
    defer tree.deinit(gpa);

    var ir = try zon2tct.IrGen.generate(gpa, tree);
    defer ir.deinit(gpa);
    if (ir.hasCompileErrors()) {
        var wip: zon2tct.ErrorBundle.Wip = undefined;
        try wip.init(gpa);
        try wip.addIrErrorMessages(ir, tree, src, comp.src_file);
        var bundle = try wip.toOwnedBundle();
        try bundle.renderToStderr(io, comp.color);
        std.process.exit(1);
    }

    const out_name = comp.provided_name orelse try mem.concat(
        comp.arena,
        u8,
        &.{ Io.Dir.path.stem(comp.src_file), ".js" },
    );

    var artifact_file = try Io.Dir.cwd().createFile(io, out_name, .{});
    defer artifact_file.close(io);
    var write_buf: [1024]u8 = undefined;
    var file_writer = artifact_file.writer(io, &write_buf);

    var e: Emit = .{
        .comp = comp,
        .ir = ir,
        .w = &file_writer.interface,
    };
    try e.emit();
}

pub const FileExt = enum {
    plaintext,
    unknown,
};

pub fn classifyFileExt(filename: []const u8) FileExt {
    if (mem.endsWith(u8, filename, ".zon") or mem.endsWith(u8, filename, ".txt")) {
        return .plaintext;
    } else {
        return .unknown;
    }
}
