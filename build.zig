const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const qjs_dir = b.path("deps/quickjs_clean");

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const qjs_module = b.createModule(.{
        .root_source_file = b.path("src/empty.zig"),
        .target = target,
        .optimize = optimize,
    });

    const qjs_lib = b.addLibrary(.{
        .name = "qjs_embed",
        .root_module = qjs_module,
        .linkage = .static,
    });
    qjs_lib.addIncludePath(qjs_dir);
    qjs_lib.addIncludePath(b.path("src"));
    qjs_lib.addCSourceFiles(.{
        .files = &.{
            "deps/quickjs_clean/dtoa.c",
            "deps/quickjs_clean/libregexp.c",
            "deps/quickjs_clean/libunicode.c",
            "deps/quickjs_clean/quickjs.c",
            "src/qjs_wrap.c",
        },
        .flags = &.{
            "-D_GNU_SOURCE",
        },
    });
    qjs_lib.linkLibC();
    if (target.result.os.tag != .windows) {
        qjs_lib.linkSystemLibrary("m");
    }

    const exe = b.addExecutable(.{
        .name = "beam",
        .root_module = root_module,
    });

    exe.addIncludePath(qjs_dir);
    exe.addIncludePath(b.path("src"));
    exe.linkLibrary(qjs_lib);
    exe.linkLibC();
    if (target.result.os.tag != .windows) {
        exe.linkSystemLibrary("m");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Beam");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_module,
    });

    tests.addIncludePath(qjs_dir);
    tests.addIncludePath(b.path("src"));
    tests.linkLibrary(qjs_lib);
    tests.linkLibC();
    if (target.result.os.tag != .windows) {
        tests.linkSystemLibrary("m");
    }

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
