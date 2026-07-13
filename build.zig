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

    const dist_path = b.graph.path(.install_prefix, "dist");
    //const make_dist_cmd = if (b.graph.host.result.os.tag == .windows)
    //    b.addSystemCommand(&.{ "mkdir", dist_path })
    //else
    //    b.addSystemCommand(&.{ "mkdir", "-p", dist_path });
    const make_dist_cmd = dist: {
        const cmd = b.addSystemCommand(&.{"mkdir"});
        if (b.graph.host.result.os.tag != .windows) {
            cmd.addArg("-p");
        }
        cmd.addDirectoryArg(dist_path);
        break :dist cmd;
    };

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

        const exe_file = release_exe.getEmittedBin();

        const compress_cmd = b.addSystemCommand(&.{"tar"});
        compress_cmd.step.dependOn(&make_dist_cmd.step);

        const archive_extension = if (res_tgt.result.os.tag == .windows) ".zip" else ".tar.gz";
        const archive_file = b.fmt("{s}{s}", .{ archive_name, archive_extension });
        const exe_filename = if (res_tgt.result.os.tag == .windows) "zon2tct.exe" else "zon2tct";
        const out_path = dist_path.path(b, archive_file);

        const flags = if (res_tgt.result.os.tag == .windows) "-acf" else "-czf";
        compress_cmd.addArg(flags);
        compress_cmd.addFileArg(out_path);
        compress_cmd.addPrefixedFileArg("-C", exe_file.dirname());
        compress_cmd.addArg(exe_filename);

        compress_cmd.step.dependOn(&release_exe.step);

        release_step.dependOn(&compress_cmd.step);
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
