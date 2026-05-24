const std = @import("std");

const zon2tct_version: std.SemanticVersion = .{ .major = 0, .minor = 3, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zon2tct_mod = b.addModule("zon2tct", .{
        .root_source_file = b.path("src/zon2tct/zon2tct.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "zon2tct",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = switch (optimize) {
                .Debug, .ReleaseSafe => false,
                .ReleaseFast, .ReleaseSmall => true,
            },
        }),
    });
    exe.root_module.addImport("zon2tct", zon2tct_mod);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const release_step = b.step("release", "Build the application for release targets");

    const dist_path = b.getInstallPath(.prefix, "dist");
    const make_dist_cmd = b.addSystemCommand(&.{
        "mkdir",
        if (b.graph.host.result.os.tag == .windows) "" else "-p",
        dist_path,
    });
    if (b.graph.host.result.os.tag == .windows) {
        _ = make_dist_cmd.argv.orderedRemove(1);
    }

    const tgts = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
    };

    const release_opt: std.lang.OptimizeMode = .ReleaseSmall;

    for (tgts) |tgt| {
        const res_tgt = b.resolveTargetQuery(tgt);

        const release_exe = b.addExecutable(.{
            .name = "zon2tct",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = res_tgt,
                .optimize = release_opt,
                .strip = switch (release_opt) {
                    .Debug, .ReleaseSafe => false,
                    .ReleaseFast, .ReleaseSmall => true,
                },
            }),
        });
        release_exe.root_module.addImport("zon2tct", zon2tct_mod);

        const tgt_str = try std.fmt.allocPrint(b.allocator, "{t}-{t}", .{ res_tgt.result.cpu.arch, res_tgt.result.os.tag });
        const archive_name = try std.fmt.allocPrint(b.allocator, "zon2tct-{s}-{d}.{d}.{d}", .{
            tgt_str,
            zon2tct_version.major,
            zon2tct_version.minor,
            zon2tct_version.patch,
        });

        const install_dir = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = tgt_str } },
        });

        const compress_cmd = b.addSystemCommand(&.{"tar"});
        compress_cmd.step.dependOn(&make_dist_cmd.step);

        if (res_tgt.result.os.tag == .windows) {
            const archive_file = try std.fmt.allocPrint(b.allocator, "dist/{s}.zip", .{archive_name});
            const out_path = b.getInstallPath(.prefix, archive_file);
            compress_cmd.addArgs(&.{ "-acf", out_path, "zon2tct.exe" });
        } else {
            const archive_file = try std.fmt.allocPrint(b.allocator, "dist/{s}.tar.gz", .{archive_name});
            const out_path = b.getInstallPath(.prefix, archive_file);
            compress_cmd.addArgs(&.{ "-czf", out_path, "zon2tct" });
        }

        compress_cmd.step.dependOn(&install_dir.step);
        compress_cmd.setCwd(.{ .cwd_relative = b.getInstallPath(.prefix, tgt_str) });

        const clean_cmd = if (b.graph.host.result.os.tag == .windows)
            b.addSystemCommand(&.{ "rmdir", "/s", "/q" })
        else
            b.addSystemCommand(&.{ "rm", "-rf" });

        clean_cmd.addArg(b.getInstallPath(.prefix, tgt_str));
        clean_cmd.step.dependOn(&compress_cmd.step);

        release_step.dependOn(&clean_cmd.step);
    }
}
