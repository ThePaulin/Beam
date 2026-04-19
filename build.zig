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

    const local_wasmtime = findLocalWasmtime();
    const wasmtime = if (enable_wasm_plugins and local_wasmtime == null) b.lazyDependency(wasmtimeDep(target.result), .{}) else null;

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
    if (enable_wasm_plugins) configureWasmtime(exe, local_wasmtime, wasmtime);

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

    const WasmExampleInstall = struct {
        plugin: ?*std.Build.Step.InstallArtifact,
        manifest: ?*std.Build.Step.InstallFile,
    };
    const wasm_example_install: WasmExampleInstall = if (enable_wasm_plugins) blk: {
        const wasm_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });
        const example_wasm_plugin_module = b.createModule(.{
            .root_source_file = b.path("examples/plugins/hello-wasm/plugin.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });
        const example_wasm_plugin = b.addExecutable(.{
            .name = "plugin",
            .root_module = example_wasm_plugin_module,
        });
        example_wasm_plugin.entry = .disabled;
        example_wasm_plugin.rdynamic = true;
        const install_plugin = b.addInstallArtifact(example_wasm_plugin, .{
            .dest_dir = .{ .override = .{ .custom = "plugins/hello-wasm" } },
        });
        const install_manifest = b.addInstallFile(
            b.path("examples/plugins/hello-wasm/plugin.toml"),
            "plugins/hello-wasm/plugin.toml",
        );
        break :blk .{ .plugin = install_plugin, .manifest = install_manifest };
    } else .{ .plugin = null, .manifest = null };

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_example_plugin.step);
    run_cmd.step.dependOn(&install_example_plugin_manifest.step);
    if (wasm_example_install.plugin) |step| run_cmd.step.dependOn(&step.step);
    if (wasm_example_install.manifest) |step| run_cmd.step.dependOn(&step.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Beam");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_module,
    });
    if (enable_wasm_plugins) configureWasmtime(tests, local_wasmtime, wasmtime);

    const run_tests = b.addRunArtifact(tests);
    if (wasm_example_install.plugin) |step| run_tests.step.dependOn(&step.step);
    if (wasm_example_install.manifest) |step| run_tests.step.dependOn(&step.step);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

fn configureWasmtime(step: *std.Build.Step.Compile, local: ?WasmtimePaths, dep: ?*std.Build.Dependency) void {
    if (local) |paths| {
        step.root_module.addSystemIncludePath(.{ .cwd_relative = paths.include_dir });
        step.addLibraryPath(.{ .cwd_relative = paths.lib_dir });
        step.linkSystemLibrary("wasmtime");
        return;
    }

    const wasmtime = dep orelse @panic("missing wasmtime dependency");
    step.root_module.addSystemIncludePath(wasmtime.path("include"));
    step.addLibraryPath(wasmtime.path("lib"));
    step.linkSystemLibrary("wasmtime");
}

const WasmtimePaths = struct {
    include_dir: []const u8,
    lib_dir: []const u8,
};

fn findLocalWasmtime() ?WasmtimePaths {
    const candidates = [_]WasmtimePaths{
        .{ .include_dir = "/opt/homebrew/include", .lib_dir = "/opt/homebrew/lib" },
        .{ .include_dir = "/usr/local/include", .lib_dir = "/usr/local/lib" },
    };

    for (candidates) |candidate| {
        const header_path = std.fs.path.join(std.heap.page_allocator, &.{ candidate.include_dir, "wasmtime.h" }) catch continue;
        defer std.heap.page_allocator.free(header_path);
        const dylib_path = std.fs.path.join(std.heap.page_allocator, &.{ candidate.lib_dir, "libwasmtime.dylib" }) catch continue;
        defer std.heap.page_allocator.free(dylib_path);
        std.fs.accessAbsolute(header_path, .{}) catch continue;
        std.fs.accessAbsolute(dylib_path, .{}) catch continue;
        return candidate;
    }
    return null;
}

fn wasmtimeDep(target: std.Target) []const u8 {
    const arch = target.cpu.arch;
    const os = target.os.tag;
    const abi = target.abi;
    return switch (os) {
        .linux => switch (arch) {
            .x86_64 => switch (abi) {
                .gnu => "wasmtime_c_api_x86_64_linux",
                .musl => "wasmtime_c_api_x86_64_musl",
                .android => "wasmtime_c_api_x86_64_android",
                else => null,
            },
            .aarch64 => switch (abi) {
                .gnu => "wasmtime_c_api_aarch64_linux",
                .android => "wasmtime_c_api_aarch64_android",
                else => null,
            },
            .s390x => "wasmtime_c_api_s390x_linux",
            .riscv64 => "wasmtime_c_api_riscv64gc_linux",
            else => null,
        },
        .windows => switch (arch) {
            .x86_64 => switch (abi) {
                .gnu => "wasmtime_c_api_x86_64_mingw",
                .msvc => "wasmtime_c_api_x86_64_windows",
                else => null,
            },
            else => null,
        },
        .macos => switch (arch) {
            .x86_64 => "wasmtime_c_api_x86_64_macos",
            .aarch64 => "wasmtime_c_api_aarch64_macos",
            else => null,
        },
        else => null,
    } orelse std.debug.panic(
        "Unsupported target for wasmtime: {s}-{s}-{s}",
        .{ @tagName(arch), @tagName(os), @tagName(abi) },
    );
}
