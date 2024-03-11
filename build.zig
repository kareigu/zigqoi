const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_name = "zigqoi";
    const lib_root = "src/qoi.zig";

    const module = b.addModule(lib_name, .{ .source_file = .{ .path = lib_root } });
    const lib = b.addStaticLibrary(.{
        .name = lib_name,
        .root_source_file = .{ .path = lib_root },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/qoi.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule(lib_name, module);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const test_executable = b.addExecutable(.{
        .name = "zigqoi_test",
        .root_source_file = .{ .path = "tests/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_executable.addModule(lib_name, module);
    b.installArtifact(test_executable);

    const run_test_executable = b.addRunArtifact(test_executable);
    if (b.args) |args| {
        run_test_executable.addArgs(args);
    }
    const run_test_executable_step = b.step("run", "Run test executable");
    run_test_executable_step.dependOn(&run_test_executable.step);
}
