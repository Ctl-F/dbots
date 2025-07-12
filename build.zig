const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "dbots",
        .root_module = exe_mod,
    });

    const zalgebra = b.dependency("zalgebra", .{}).module("zalgebra");

    exe.root_module.addImport("zalgebra", zalgebra);

    exe.linkLibC();
    exe.linkSystemLibrary("SDL3");
    exe.addCSourceFile(.{ .file = b.path("src/c/stb_image.c"), .language = .c });
    exe.addIncludePath(b.path("src/c/"));

    build_shaders(b, exe) catch unreachable;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn build_shaders(b: *std.Build, exe: *std.Build.Step.Compile) !void {
    const shaders_folder = "zig-out/bin/assets/shaders";

    const cwd = try std.fs.cwd().openDir(shaders_folder, .{ .iterate = true });
    var walker = try cwd.walk(b.allocator);

    std.debug.print("Compiling shaders...\n", .{});

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        if (!std.mem.endsWith(u8, entry.basename, ".glsl")) {
            continue;
        }

        const name_no_ext = entry.basename[0 .. entry.basename.len - ".glsl".len];

        const name_new_ext = try std.mem.concat(b.allocator, u8, &.{ name_no_ext, ".spv" });
        defer b.allocator.free(name_new_ext);

        const output_path = try std.fs.path.join(b.allocator, &.{ shaders_folder, name_new_ext });
        defer b.allocator.free(output_path);

        const input_path = try std.fs.path.join(b.allocator, &.{ shaders_folder, entry.basename });
        defer b.allocator.free(input_path);

        const stage = STAGE: {
            if (std.mem.endsWith(u8, name_no_ext, ".vert")) {
                break :STAGE "-fshader-stage=vert";
            }
            if (std.mem.endsWith(u8, name_no_ext, ".frag")) {
                break :STAGE "-fshader-stage=frag";
            }

            break :STAGE "";
        };

        if (stage.len == 0) {
            continue;
        }

        const step = b.addSystemCommand(&.{
            "glslc",
            stage,
            input_path,
            "-o",
            output_path,
        });

        std.debug.print("-- {s}: `glslc {s} {s} -o {s}`\n", .{ entry.basename, stage, input_path, output_path });

        exe.step.dependOn(&step.step);
    }
}
