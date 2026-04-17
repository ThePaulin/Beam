const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "beam",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const plugin_api_module = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    const example_plugin_module = b.createModule(.{
        .root_source_file = b.path("examples/plugins/hello/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "beam", .module = plugin_api_module }},
    });
    const example_plugin = b.addLibrary(.{
        .name = "beam_plugin",
        .root_module = example_plugin_module,
        .linkage = .dynamic,
    });
    const install_example_plugin = b.addInstallArtifact(example_plugin, .{
        .dest_dir = .{ .override = .{ .custom = "plugins/hello" } },
    });
    const install_example_plugin_manifest = b.addInstallFile(
        b.path("examples/plugins/hello/plugin.toml"),
        "plugins/hello/plugin.toml",
    );

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_example_plugin.step);
    run_cmd.step.dependOn(&install_example_plugin_manifest.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Beam");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
