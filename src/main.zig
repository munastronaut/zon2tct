const std = @import("std");
const Io = std.Io;
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;

const Transpiler = @import("Transpiler.zig");
const SymbolTable = @import("SymbolTable.zig");
const ErrorCollector = @import("ErrorCollector.zig");
const common = @import("common.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena;
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        std.debug.print("Usage: {s} <input> [output]\n", .{args[0]}); // I'll use a proper stderr writer for this soon
        return;
    }

    const input_path = args[1];
    const output_path = if (args.len > 2) args[2] else "code2.js";

    const src = try Io.Dir.cwd().readFileAllocOptions(io, input_path, allocator, .limited(10 * 1024 * 1024), .@"8", 0);

    var symbols = SymbolTable.init(allocator);

    var collector = ErrorCollector.init(allocator);

    var ast = try Ast.parse(allocator, src, .zon);

    if (ast.errors.len > 0) {
        for (ast.errors) |err| {
            const loc_info = ast.tokenLocation(0, err.token);
            const loc: common.Location = .{ .line = loc_info.line + 1, .column = loc_info.column + 1 };

            const tok_slice = ast.tokenSlice(err.token);
            const len = if (tok_slice.len > 0) tok_slice.len else 1;

            const msg = switch (err.tag) {
                // Yes these can be vague, and they can point to the wrong line.
                // Please suggest better error messages if you see this!
                .expected_comma_after_field, .expected_comma_after_initializer => "i expected a ',' here to separate these fields.",
                .expected_token, .expected_initializer => "i expected a token or initializer here.",

                // NOTE TO SELF:
                // Implement this catch-all if most errors are accounted for:
                //     i'm confused by the structure, can you check this line?
                //
                // I'm keeping this placeholder for debugging, and to see where it comes up the most.
                else => try std.fmt.allocPrint(allocator, "PLACEHOLDER: {s}\n", .{@tagName(err.tag)}),
            };

            try collector.report(.@"error", .underline, loc, len, msg, null);
        }

        try collector.render(io, input_path, src);
        std.process.exit(1);
    }

    const root_data = ast.nodes.items(.data)[0];
    const root_expr_idx = root_data.node;

    var transpiler = Transpiler.init(arena, &symbols, &collector);

    if (common.findField(&ast, root_expr_idx, "definitions")) |defs_node|
        try symbols.populateTable(allocator, &ast, defs_node, &collector);

    if (common.findField(&ast, root_expr_idx, "player_candidate")) |pc_node| {
        const id = try transpiler.resolveId(&ast, pc_node, .candidates);
        transpiler.player_id = try std.fmt.allocPrint(allocator, "{d}", .{id});
    }

    if (common.findField(&ast, root_expr_idx, "questions")) |questions_node|
        try transpiler.transpile(&ast, questions_node);

    if (transpiler.collector.has_errors) {
        try transpiler.collector.render(io, input_path, src);
        std.process.exit(1);
    }

    const output_file = try Io.Dir.cwd().createFile(io, output_path, .{});
    defer output_file.close(io);

    var output_buffer: [4096]u8 = undefined;
    var writer = output_file.writer(io, &output_buffer);
    const output = &writer.interface;

    const manifest = if (symbols.manifest.count() > 0) blk: {
        var list: std.ArrayList(u8) = .empty;
        try list.appendSlice(allocator, "const SYMBOLS = {\n");

        var sym_it = symbols.manifest.iterator();
        while (sym_it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (common.isValidJSIdentifier(key)) {
                try list.print(
                    allocator,
                    "  {s}: {d},\n",
                    .{ key, value },
                );
            } else {
                try list.print(
                    allocator,
                    "  \"{s}\": {d},\n",
                    .{ key, value },
                );
            }
        }
        try list.appendSlice(allocator, "};\n\n");
        break :blk try list.toOwnedSlice(allocator);
    } else "";

    try output.print(
        \\{s}e ||= campaignTrail_temp;
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
    ,
        .{
            manifest,
            transpiler.questions.items,
            transpiler.answers.items,
            transpiler.global_effects.items,
            transpiler.issue_effects.items,
            transpiler.state_effects.items,
            transpiler.feedbacks.items,
        },
    );
    try output.flush();
}
