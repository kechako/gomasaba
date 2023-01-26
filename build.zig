const std = @import("std");

const gomasaba_version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("gomasaba", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const version_string = b.fmt("{d}.{d}.{d}", .{ gomasaba_version.major, gomasaba_version.minor, gomasaba_version.patch });
    const version = try b.allocator.dupeZ(u8, version_string);

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([:0]const u8, "version", version);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
