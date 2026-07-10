const std = @import("std");

const zon2tct_version: std.SemanticVersion = .{ .major = 0, .minor = 3, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addCompilerStep(b, .{
        .optimize = optimize,
        .target = target,
        .strip = switch (optimize) {
            .Debug, .ReleaseSafe => false,
            .ReleaseFast, .ReleaseSmall => true,
        },
    });

    const zon2tct_mod = b.addModule("zon2tct", .{
        .root_source_file = b.path("src/zon2tct/zon2tct.zig"),
    });
    exe.root_module.addImport("zon2tct", zon2tct_mod);

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);

    const version_str = b.fmt("{d}.{d}.{d}", .{
        zon2tct_version.major,
        zon2tct_version.minor,
        zon2tct_version.patch,
    });
    const version = try b.allocator.dupeSentinel(u8, version_str, 0);

    exe_options.addOption([:0]const u8, "version", version);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const release_step = b.step("release", "Build the application for release targets");

    //const dist_path = b.getInstallPath(.prefix, "dist");
    const dist_path = b.fmt("{f}", .{b.graph.path(.install_prefix, "dist")});
    const make_dist_cmd = if (b.graph.host.result.os.tag == .windows)
        b.addSystemCommand(&.{ "mkdir", dist_path })
    else
        b.addSystemCommand(&.{ "mkdir", "-p", dist_path });

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

        const release_exe = addCompilerStep(b, .{
            .optimize = release_opt,
            .target = res_tgt,
            .strip = switch (release_opt) {
                .Debug, .ReleaseSafe => false,
                .ReleaseFast, .ReleaseSmall => true,
            },
        });
        release_exe.root_module.addImport("zon2tct", zon2tct_mod);
        release_exe.root_module.addOptions("build_options", exe_options);

        const tgt_str = b.fmt("{t}-{t}", .{ res_tgt.result.cpu.arch, res_tgt.result.os.tag });
        const archive_name = b.fmt("zon2tct-{s}-{d}.{d}.{d}", .{
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
            const archive_file = b.fmt("dist/{s}.zip", .{archive_name});
            const out_path = b.fmt("{f}", .{b.graph.path(.install_prefix, archive_file)});
            compress_cmd.addArgs(&.{ "-acf", out_path, "zon2tct.exe" });
        } else {
            const archive_file = b.fmt("dist/{s}.tar.gz", .{archive_name});
            const out_path = b.fmt("{f}", .{b.graph.path(.install_prefix, archive_file)});
            compress_cmd.addArgs(&.{ "-czf", out_path, "zon2tct" });
        }

        compress_cmd.step.dependOn(&install_dir.step);
        compress_cmd.setCwd(.{ .cwd_relative = b.fmt("{f}", .{b.graph.path(.install_prefix, tgt_str)}) });

        const clean_cmd = if (b.graph.host.result.os.tag == .windows)
            b.addSystemCommand(&.{ "rmdir", "/s", "/q" })
        else
            b.addSystemCommand(&.{ "rm", "-rf" });

        clean_cmd.addArg(b.fmt("{f}", .{b.graph.path(.install_prefix, tgt_str)}));
        clean_cmd.step.dependOn(&compress_cmd.step);

        release_step.dependOn(&clean_cmd.step);
    }
}

const AddCompilerModOptions = struct {
    optimize: std.lang.OptimizeMode,
    target: std.Build.ResolvedTarget,
    strip: ?bool = null,
};

fn addCompilerMod(b: *std.Build, options: AddCompilerModOptions) *std.Build.Module {
    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = options.strip,
    });

    return compiler_mod;
}

fn addCompilerStep(b: *std.Build, options: AddCompilerModOptions) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zon2tct",
        .root_module = addCompilerMod(b, options),
    });
}
