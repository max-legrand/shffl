const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlog = b.dependency("zlog", .{ .target = target, .optimize = optimize });
    const tanuki = b.dependency("tanuki", .{ .target = target, .optimize = optimize });
    const multitool = b.dependency("multitool", .{ .target = target, .optimize = optimize });
    const zul = b.dependency("zul", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "shffl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zlog", .module = zlog.module("zlog") },
                .{ .name = "tanuki", .module = tanuki.module("tanuki") },
                .{ .name = "multitool", .module = multitool.module("multitool") },
                .{ .name = "zul", .module = zul.module("zul") },
            },
            .link_libc = true,
        }),
    });
    exe.use_llvm = true;

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
