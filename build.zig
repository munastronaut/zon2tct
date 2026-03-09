const std = @import("std");

pub fn build(b: *std.Build) void {
    //const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
    };

    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p" });
    mkdir_step.addArg(b.getInstallPath(.bin, ""));

    const release_step = b.step("release", "Build for all platforms");

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const os = target.result.os.tag;
        const arch = target.result.cpu.arch;

        const exe = b.addExecutable(.{
            .name = "zon2tct",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .strip = true,
            }),
        });

        const target_name = b.fmt("{s}-{s}", .{ @tagName(arch), @tagName(os) });
        const artifact = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = target_name } },
        });

        const tar_gz = createArchiveStep(b, target_name, ".tar.gz", artifact, mkdir_step);
        release_step.dependOn(&tar_gz.step);

        if (os == .windows) {
            const zip = createArchiveStep(b, target_name, ".zip", artifact, mkdir_step);
            release_step.dependOn(&zip.step);
        }
    }
}

fn createArchiveStep(b: *std.Build, target_name: []const u8, extension: []const u8, install_step: *std.Build.Step.InstallArtifact, mkdir_step: *std.Build.Step.Run) *std.Build.Step.Run {
    const archive_name = b.fmt("zon2tct-{s}{s}", .{ target_name, extension });

    const tar_cmd = b.addSystemCommand(&.{ "tar", "-caf" });

    const archive_path = b.getInstallPath(.bin, archive_name);
    tar_cmd.addArg(archive_path);

    tar_cmd.addArg("-C");
    const src_dir = b.getInstallPath(.prefix, target_name);
    tar_cmd.addArg(src_dir);

    tar_cmd.addArg(".");

    tar_cmd.step.dependOn(&install_step.step);
    tar_cmd.step.dependOn(&mkdir_step.step);

    return tar_cmd;
}
