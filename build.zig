const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_wasm_plugins = b.option(bool, "wasm-plugins", "Enable experimental WASM plugin manifests and runtime loading") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_wasm_plugins", enable_wasm_plugins);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addOptions("build_options", build_options);

    const tree_sitter_lib = b.addLibrary(.{
        .name = "tree-sitter",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    // Keep the parser runtime vendored so Beam builds the exact C runtime it links against.
    tree_sitter_lib.root_module.addCMacro("_POSIX_C_SOURCE", "200112L");
    tree_sitter_lib.root_module.addCMacro("_DEFAULT_SOURCE", "");
    tree_sitter_lib.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-runtime/lib/src/lib.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_lib.addIncludePath(b.path("vendor/tree-sitter-runtime/lib/include"));
    tree_sitter_lib.addIncludePath(b.path("vendor/tree-sitter-runtime/lib/src"));
    const tree_sitter_module = b.addModule("tree-sitter", .{
        .root_source_file = b.path("vendor/tree-sitter-bindings/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_module.linkLibrary(tree_sitter_lib);
    root_module.addImport("tree-sitter", tree_sitter_module);

    const tree_sitter_zig_lib = b.addLibrary(.{
        .name = "tree-sitter-zig",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    // The Zig grammar is also vendored and compiled directly into the Beam binary.
    tree_sitter_zig_lib.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_zig_lib.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    const tree_sitter_zig_module = b.addModule("tree-sitter-zig", .{
        .root_source_file = b.path("vendor/tree-sitter-zig/bindings/zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_zig_module.linkLibrary(tree_sitter_zig_lib);
    root_module.addImport("tree-sitter-zig", tree_sitter_zig_module);

    // Embed query sources so the executable does not need to read them from the checkout at runtime.
    const tree_sitter_queries = b.addWriteFiles();
    _ = tree_sitter_queries.addCopyFile(b.path("vendor/tree-sitter-zig/queries/highlights.scm"), "highlights.scm");
    _ = tree_sitter_queries.addCopyFile(b.path("vendor/tree-sitter-zig/queries/locals.scm"), "locals.scm");
    _ = tree_sitter_queries.addCopyFile(b.path("vendor/tree-sitter-zig/queries/folds.scm"), "folds.scm");
    const tree_sitter_queries_source = tree_sitter_queries.add(
        "queries.zig",
        \\pub const zig_highlights_query_source = @embedFile("highlights.scm");
        \\pub const zig_locals_query_source = @embedFile("locals.scm");
        \\pub const zig_folds_query_source = @embedFile("folds.scm");
    );
    const tree_sitter_queries_module = b.addModule("tree-sitter-queries", .{
        .root_source_file = tree_sitter_queries_source,
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("tree-sitter-queries", tree_sitter_queries_module);

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
    plugin_api_module.addOptions("build_options", build_options);
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
