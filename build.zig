const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("lil-scan", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "lil-scan",
        .root_module = mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    run_lib_unit_tests.has_side_effects = true; // always re-run tests

    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    if (coverage) {
        const runner = [_][]const u8{
            "kcov",
            "--include-path",
            ".",
            "--clean",
            "coverage", // output dir
        };

        const dst = try run_lib_unit_tests.argv.addManyAt(b.allocator, 0, runner.len);
        for (runner, 0..) |arg, idx| {
            dst[idx] = .{ .bytes = b.dupe(arg) };
        }
    }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const demo_err = b.addExecutable(.{
        .name = "lil-demo-err",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo-err.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo_err.root_module.addImport("lil-scan", mod);
    b.installArtifact(demo_err);

    const demo_calc = b.addExecutable(.{
        .name = "lil-demo-calc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo-calc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo_calc.root_module.addImport("lil-scan", mod);
    b.installArtifact(demo_calc);
}
