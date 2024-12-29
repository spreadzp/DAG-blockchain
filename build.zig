const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main blockchain executable

    // CLI executable
    const cli_exe = b.addExecutable(.{
        .name = "dag-cli",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(cli_exe);
    const cli_run_cmd = b.addRunArtifact(cli_exe);
    cli_run_cmd.step.dependOn(b.getInstallStep());
    const cli_run_step = b.step("cli", "Run the blockchain CLI");
    cli_run_step.dependOn(&cli_run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
