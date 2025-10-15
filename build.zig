const std = @import("std");
const crab = @import("build_crab");

pub fn build(b: *std.Build) !void {
    b.addNamedLazyPath("include", b.path("c-api/include"));

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const translate_header = b.addTranslateC(.{
        .root_source_file = b.path("c-api/include/unicode_ident.h"),
        .optimize = optimize,
        .target = target,
    });
    const translated = translate_header.addModule("unicode-ident-c");

    const cargo_build: *CargoBuild = .create(b, .{
        .manifest_path = b.path("Cargo.toml"),
        .release = optimize != .Debug,
        .target = try .fromZig(target.result),
    });

    const target_dir = cargo_build.getOutput();
    b.addNamedLazyPath("target", target_dir);

    const lib = try target_dir.join(
        b.allocator,
        b.fmt("{s}unicode_ident{s}", .{
            target.result.libPrefix(),
            target.result.staticLibSuffix(),
        }),
    );
    b.addNamedLazyPath("lib", lib);

    const binding = b.addModule("unicode-ident", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    binding.addObjectFile(lib);
    binding.addImport("c-api", translated);

    const test_binding = b.addTest(.{ .root_module = binding });
    const run_tests = b.addRunArtifact(test_binding);

    b.step("test", "Run Zig tests")
        .dependOn(&run_tests.step);
}

const CargoBuild = struct {
    const GeneratedFile = std.Build.GeneratedFile;
    const LazyPath = std.Build.LazyPath;
    const Step = std.Build.Step;

    step: Step,
    output: GeneratedFile,

    manifest_path: LazyPath,
    release: bool,
    target: crab.rust.Target,

    const Options = struct {
        manifest_path: LazyPath,
        target: crab.rust.Target,
        release: bool,
    };

    pub fn create(b: *std.Build, opts: Options) *CargoBuild {
        const cb = b.allocator.create(CargoBuild) catch @panic("OOM");

        cb.* = .{
            .step = Step.init(.{
                .name = "cargo build",
                .owner = b,
                .makeFn = make,
                .id = .custom,
            }),
            .output = .{ .step = &cb.step },
            .manifest_path = opts.manifest_path,
            .release = opts.release,
            .target = opts.target,
        };

        return cb;
    }

    pub fn getOutput(self: *CargoBuild) LazyPath {
        return LazyPath{ .generated = .{
            .file = &self.output,
        } };
    }

    fn make(step: *Step, options: Step.MakeOptions) !void {
        const b = step.owner;
        const cb: *CargoBuild = @fieldParentPtr("step", step);

        errdefer |err| {
            std.log.err("error during cargo build step: {}", .{err});
        }

        const target_dir = try b.cache_root.join(
            b.allocator,
            &.{ "cargo", "unicode-ident" },
        );

        const target = b.fmt("{f}", .{cb.target});

        var argv: std.ArrayList([]const u8) = .empty;
        const manifest_path = cb.manifest_path.getPath3(b, step);
        try argv.appendSlice(b.allocator, &.{
            "cargo",           "build",
            "--manifest-path", manifest_path.toString(b.allocator) catch @panic("OOM"),
            "--target",        target,
            "--package",       "c-api",
            "--target-dir",    target_dir,
        });
        if (cb.release) try argv.append(b.allocator, "--release");

        const progress_node = options.progress_node.start("cargo build", 1);
        defer progress_node.end();

        var cargo_build = std.process.Child.init(argv.items, b.allocator);
        cargo_build.stdin_behavior = .Ignore;
        cargo_build.stdout_behavior = .Pipe;
        cargo_build.stderr_behavior = .Inherit;

        try cargo_build.spawn();
        errdefer _ = cargo_build.kill() catch {};

        const term = try cargo_build.wait();
        if (term != .Exited) unreachable;

        if (term.Exited != 0) {
            try step.addError("cargo build failed", .{});
            return error.MakeFailed;
        }

        cb.output.path = b.pathJoin(&.{
            target_dir, target, if (cb.release) "release" else "debug",
        });
    }
};
