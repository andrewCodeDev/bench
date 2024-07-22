const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast
    });

    const exe = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(b.path("src"));

    exe.addCSourceFile(.{
        .file = b.path("src/hw_counter.c"),
        .flags = &.{ "-O3" }
    });

    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    const run_step = b.step("run", "run stats test");

    run_step.dependOn(&run_cmd.step);
}
