const std = @import("std");
const Io = std.Io;
const Build = std.Build;

const zon2tct_version: std.SemanticVersion = .{ .major = 0, .minor = 4, .patch = 1 };

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addCompilerStep(b, .{
        .optimize = optimize,
        .target = target,
        .strip = !optimize.runtimeSafety(),
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

    const tgts = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
    };

    const release_opt: std.lang.OptimizeMode = .small;

    const archiver_exe = b.addExecutable(.{
        .name = "archiver",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/archiver.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });

    for (tgts) |tgt| {
        const res_tgt = b.resolveTargetQuery(tgt);

        const release_exe = addCompilerStep(b, .{
            .optimize = release_opt,
            .target = res_tgt,
            .strip = !release_opt.runtimeSafety(),
        });
        release_exe.root_module.addImport("zon2tct", zon2tct_mod);
        release_exe.root_module.addOptions("build_options", exe_options);

        const is_windows = res_tgt.result.os.tag == .windows;
        const archive_ext = if (is_windows) ".zip" else ".tar.gz";

        const tgt_str = b.fmt("{t}-{t}", .{ res_tgt.result.cpu.arch, res_tgt.result.os.tag });
        const archive_name = b.fmt("zon2tct-{s}-{d}.{d}.{d}", .{
            tgt_str,
            zon2tct_version.major,
            zon2tct_version.minor,
            zon2tct_version.patch,
        });

        const archive_filename = b.fmt("{s}{s}", .{ archive_name, archive_ext });

        const archive_cmd = b.addRunArtifact(archiver_exe);
        archive_cmd.addFileArg(release_exe.getEmittedBin());
        const archived_file = archive_cmd.addOutputFileArg2(b.fmt("dist/{s}{s}", .{ archive_name, archive_ext }), .{});

        const archive = b.addInstallFileWithDir(archived_file, .{ .custom = "dist" }, archive_filename);
        release_step.dependOn(&archive.step);
    }
}

const AddCompilerModOptions = struct {
    optimize: std.lang.OptimizeMode,
    target: Build.ResolvedTarget,
    strip: ?bool = null,
};

fn addCompilerMod(b: *Build, options: AddCompilerModOptions) *Build.Module {
    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = options.strip,
    });

    return compiler_mod;
}

fn addCompilerStep(b: *Build, options: AddCompilerModOptions) *Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zon2tct",
        .root_module = addCompilerMod(b, options),
    });
}
