const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const translate_header = b.addTranslateC(.{
        .root_source_file = b.path("c-api/include/unicode_ident.h"),
        .optimize = optimize,
        .target = target,
    });
    const translated = translate_header.addModule("unicode-ident-c");

    const cargo_build = CargoBuild.create(b, .{
        .manifest_path = b.path("Cargo.toml"),
        .optimize = optimize,
        .target = target,
    });

    b.addNamedLazyPath("staticlib", cargo_build.getOutput());
    b.addNamedLazyPath("include", b.path("c-api/include"));

    const binding = b.addModule("unicode-ident", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    binding.addObjectFile(cargo_build.getOutput());
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
    output: *GeneratedFile,

    manifest_path: LazyPath,
    release: bool,
    target: []const u8,
    package: ?[]const u8,

    const Options = struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        manifest_path: LazyPath,
    };

    pub fn create(b: *std.Build, opts: Options) *CargoBuild {
        const cb = b.allocator.create(CargoBuild) catch @panic("OOM");

        const generated_file = b.allocator.create(GeneratedFile) catch @panic("OOM");
        generated_file.* = .{ .step = &cb.step };

        cb.* = .{
            .step = Step.init(.{
                .name = "cargo build",
                .owner = b,
                .makeFn = make,
                .id = .custom,
            }),
            .package = "c-api",
            .output = generated_file,
            .manifest_path = opts.manifest_path,
            .release = opts.optimize != .Debug,
            .target = cargoTriple(b, opts.target),
        };

        return cb;
    }

    fn cargoTriple(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
        const arch = switch (target.result.cpu.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "aarch64",
            else => @panic("unrecognized architecture"),
        };

        const with_os = switch (target.result.os.tag) {
            .linux => b.fmt("{s}-unknown-linux", .{arch}),
            .macos => b.fmt("{s}-apple-darwin", .{arch}),
            else => @panic("unrecognized OS"),
        };

        return switch (target.result.abi) {
            inline .macabi,
            .gnu,
            .gnueabi,
            .gnueabihf,
            .eabi,
            .eabihf,
            => |tag| b.fmt("{s}-{s}", .{ arch, @tagName(tag) }),
            else => with_os,
        };
    }

    pub fn getOutput(self: *CargoBuild) LazyPath {
        return LazyPath{ .generated = .{
            .file = self.output,
        } };
    }

    fn make(step: *Step, options: Step.MakeOptions) !void {
        const b = step.owner;
        const cb: *CargoBuild = @fieldParentPtr("step", step);

        errdefer |err| {
            std.log.err("error during cargo build step: {}", .{err});
        }

        var argv: std.ArrayList([]const u8) = .empty;
        const manifest_path = cb.manifest_path.getPath3(b, step);
        try argv.appendSlice(b.allocator, &.{
            "cargo",            "build",
            "--manifest-path",  manifest_path.toString(b.allocator) catch @panic("OOM"),
            "--target",         cb.target,
            "--message-format", "json",
        });
        if (cb.release) try argv.append(b.allocator, "--release");
        if (cb.package) |package|
            try argv.appendSlice(b.allocator, &.{ "--package", package });

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

        var output_path = b.path("target");
        output_path = try output_path.join(b.allocator, cb.target);
        output_path = try output_path.join(b.allocator, if (cb.release) "release" else "debug");
        output_path = try output_path.join(b.allocator, "libunicode_ident.a");

        cb.output.path = try output_path.getPath3(b, step).toString(b.allocator);
    }
};
