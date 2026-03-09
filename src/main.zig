const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;

const Transpiler = @import("Transpiler.zig");
const SymbolTable = @import("SymbolTable.zig");
const ErrorCollector = @import("ErrorCollector.zig");
const common = @import("common.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("Usage: {s} <input> [output]\n", .{args[0]}); // I'll use a proper stderr writer for this soon
        return;
    }

    const input_path = args[1];
    const output_path = if (args.len > 2) args[2] else "code2.js";

    const src = try Io.Dir.cwd().readFileAllocOptions(init.io, input_path, allocator, .limited(10 * 1024 * 1024), .@"8", 0);
    defer allocator.free(src);

    var ast = try Ast.parse(allocator, src, .zon);
    defer ast.deinit(allocator);

    const root_data = ast.nodes.items(.data)[0];
    const root_expr_idx = root_data.node;

    var symbols = SymbolTable.init(allocator);
    defer symbols.deinit();

    var collector = ErrorCollector.init(allocator);
    defer collector.deinit();

    var transpiler = Transpiler.init(init.arena, &symbols, &collector);

    if (common.findField(&ast, root_expr_idx, "definitions")) |defs_node|
        try symbols.populateTable(arena, &ast, defs_node);

    if (common.findField(&ast, root_expr_idx, "player_candidate")) |pc_node| {
        const id = try transpiler.resolveId(&ast, pc_node, .candidates);
        transpiler.player_id = try std.fmt.allocPrint(arena, "{d}", .{id});
    }

    if (common.findField(&ast, root_expr_idx, "questions")) |questions_node|
        try transpiler.transpile(&ast, questions_node);

    if (transpiler.collector.has_errors) {
        try transpiler.collector.render(init.io, input_path, src);
        std.process.exit(1);
    }

    const output_file = try Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer output_file.close(init.io);

    var output_buffer: [4096]u8 = undefined;
    var writer = output_file.writer(init.io, &output_buffer);
    var output_writer = &writer.interface;

    try output_writer.print(
        \\e = campaignTrail_temp;
        \\
        \\e.questions_json = [{s}];
        \\
        \\e.answers_json = [{s}];
        \\
        // States json here
        // Issues json here
        // State issue scores json here
        // Candidate issue scores json here
        // Running mate issue scores json here
        // Candidate state multiplier json here
        \\e.answer_score_global_json = [{s}];
        \\
        \\e.answer_score_issue_json = [{s}];
        \\
        \\e.answer_score_state_json = [{s}];
        \\
        \\e.answer_feedback_json = [{s}];
        \\
    , .{ transpiler.questions.items, transpiler.answers.items, transpiler.global_effects.items, transpiler.issue_effects.items, transpiler.state_effects.items, transpiler.feedbacks.items });
    try output_writer.flush();
}
