const std = @import("std");

const zon2tct_version: std.SemanticVersion = .{ .major = 0, .minor = 3, .patch = 0 };

pub fn build(b: *std.Build) void {
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
}
