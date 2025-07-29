const std = @import("std");
const host = @import("host.zig");
const assets = @import("assets.zig");
const math = @import("math.zig");
const UI = @import("ui.zig");
const Camera = @import("camera.zig");
const Time = @import("timing.zig");

const UniformColor = extern struct {
    color: [4]f32,
};

const UniformTransform = extern struct {
    projection: math.mat4,
    view: math.mat4,
    model: math.mat4,
    magic_id: f32,
};

pub fn main() !void {
    const options = host.InitOptions{
        .display = .{ .width = 800, .height = 600, .monitor = null, .vsync = false },
        .title = "Deathbots",
    };
    std.debug.print("Initializing\n", .{});

    try host.init(options);
    defer host.deinit();

    std.debug.print("Loading shaders\n", .{});

    var scene = assets.SceneResources.init(host.MemAlloc);
    defer scene.deinit();

    try scene.load(&[_]assets.ResourceRequest{
        assets.ResourceRequest{
            .asset_name = "basic_vert",
            .asset_source = "shaders/Basic.vert.spv",
            .type = .{
                .shader = .{
                    .stage = .Vertex,
                    .resources = .{
                        .sampler_count = 0,
                        .storage_buffer_count = 0,
                        .storage_texture_count = 0,
                        .uniform_buffer_count = 1,
                    },
                },
            },
        },
        assets.ResourceRequest{
            .asset_name = "basic_frag",
            .asset_source = "shaders/Basic.frag.spv",
            .type = .{
                .shader = .{
                    .stage = .Fragment,
                    .resources = .{
                        .sampler_count = 1,
                        .storage_buffer_count = 0,
                        .storage_texture_count = 0,
                        .uniform_buffer_count = 1,
                    },
                },
            },
        },
        assets.ResourceRequest{
            .asset_name = "dragon_eye",
            .asset_source = "sprites/DragonEye.png",
            .type = .{
                .texture = .{
                    .vflip = true,
                },
            },
        },
        assets.ResourceRequest{
            .asset_name = "basic_plane",
            .asset_source = "meshes/Monkey.rvb",
            .type = .{
                .mesh = .{ .vertex_count = undefined },
            },
        },
        assets.ResourceRequest{
            .asset_name = "main_font",
            .asset_source = "fonts/DUNSTA__.TTF",
            .type = .{
                .font = .{ .size = 16 },
            },
        },
        assets.ResourceRequest{
            .asset_name = "cube",
            .asset_source = "meshes/Cube.rvb",
            .type = .{
                .mesh = .{ .vertex_count = undefined },
            },
        },
    });

    var format: host.VertexFormat = undefined;
    assets.Vertex.fmt(&format);

    const pipelineInfo = host.PipelineConfig{
        .vertex_shader = scene.get(assets.Shader, "basic_vert") orelse unreachable,
        .fragment_shader = scene.get(assets.Shader, "basic_frag") orelse unreachable,
        .topology = .TriangleList,
        .vertex_format = format,
        .enable_depth_buffer = true,
        .enable_culling = false,
    };
    const pipeline = try host.Pipeline.init(pipelineInfo);
    defer pipeline.free();

    try scene.build_default_assets();
    {
        var copyPass = host.CopyPass.init(host.MemAlloc);
        defer copyPass.deinit();

        const plane_ref = scene.get_lookup_info("basic_plane") orelse unreachable;
        std.debug.assert(plane_ref == .mesh);
        const bufferInfo = host.BufferCreateInfo{
            .dynamic_upload = false,
            .element_size = @sizeOf(assets.Vertex),
            .num_elements = @intCast(plane_ref.mesh.vertex_count),
            .texture_info = null,
            .usage = .Vertex,
        };
        _ = try scene.add_buffer_copy(.{
            .source_name = "basic_plane",
            .dest_name = "floor",
            .info = bufferInfo,
        }, &copyPass);

        const cube = scene.get_lookup_info("cube") orelse unreachable;
        const cubeInfo = host.BufferCreateInfo{
            .dynamic_upload = false,
            .element_size = @sizeOf(assets.Vertex),
            .num_elements = @intCast(cube.mesh.vertex_count),
            .texture_info = null,
            .usage = .Vertex,
        };
        _ = try scene.add_buffer_copy(.{
            .source_name = "cube",
            .dest_name = "cube_mesh",
            .info = cubeInfo,
        }, &copyPass);

        const dreye_ref = scene.get(assets.SoftwareTexture, "dragon_eye") orelse unreachable;

        _ = try scene.add_texture_copy(.{
            .source_name = "dragon_eye",
            .dest_name = "gpu_dragon_eye",
            .info = .{
                .address_policy = .Repeat,
                .enable_mipmaps = false,
                .width = dreye_ref.width,
                .height = dreye_ref.height,
                .mag_filter = .Linear,
                .min_filter = .Linear,
                .mipmap_filter = .Nearest,
                .texture_name = "dragon_eye",
            },
        }, &copyPass);

        try copyPass.submit();

        try scene.claim_copy_result(host.GPUTexture, copyPass, "gpu_dragon_eye");
        try scene.claim_copy_result(host.GPUBuffer, copyPass, "floor");
        try scene.claim_copy_result(host.GPUBuffer, copyPass, "cube_mesh");
        copyPass.claim_ownership_of_results();
    }

    // we don't need to release the texture anymore becauser it's now owned by the scene.
    //const texture = scene.get(host.GPUTexture, "gpu_dragon_eye") orelse unreachable;

    const textures = [_]host.GPUTexture{
        scene.get(host.GPUTexture, "gpu_dragon_eye") orelse unreachable,
        scene.get(host.GPUTexture, assets.Default.CheckerBoard) orelse unreachable,
    };

    const gpuBuffer = scene.get(host.GPUBuffer, "floor") orelse unreachable;
    const cube = scene.get(host.GPUBuffer, "cube_mesh") orelse unreachable;

    scene.free_resource("basic_vert");
    scene.free_resource("basic_frag");

    var camera = Camera.PerspectiveCamera.init(90.0, @as(f32, @floatFromInt(options.display.width)) / @as(f32, @floatFromInt(options.display.height)), 0.01, math.vec3.up());

    var color: UniformColor = .{ .color = @splat(1) };
    var transform: UniformTransform = .{
        .projection = camera.projection,
        .view = undefined,
        .model = math.mat4.identity(),
        .magic_id = 42,
    };

    host.input_mode(.Keyboard);
    var input = host.input();

    var ui = try UI.init(@floatFromInt(options.display.width), @floatFromInt(options.display.height), 0.01, 100.0, &scene, "main_font", .English);
    try ui.debug_render_string_fmt(null, 0, 0, null, "FrameTime: {} - Pitch: {}", .{ 0, 0 });
    //***TEMPORARY***
    try ui.language_pack.gen_textures();

    std.debug.print("Starting main loop\n", .{});

    var timer = Time.Timer.start();

    app: while (!input.should_close()) {
        input.process_events();
        const dt = timer.delta();
        {
            const move_axis = input.axis();

            const local_move = math.vec3.new(move_axis[0], 0, move_axis[1]);
            const world_move = camera.angle.rotateVec(local_move);
            const flat_move = math.vec3.new(world_move.x(), 0, world_move.z());

            if (flat_move.lengthSq() > std.math.floatEps(f32)) {
                const move_vector = flat_move.norm().scale(0.1);
                camera.position = camera.position.add(move_vector);
            }

            // const forward = camera.angle.rotateVec(math.vec3.new(move_axis[0], 0, move_axis[1]));
            // const move_vector = math.vec3.new(forward.x(), 0, forward.z()).norm().scale(0.1); // correct scale TODO: Timers and DeltaTime
            // if (@abs(move_vector.lengthSq()) > std.math.floatEps(f32)) {
            //     camera.position = camera.position.add(move_vector);
            // }
        }

        {
            const hmov = input.mouse_x_rel * 0.1;
            const vmov = input.mouse_y_rel * 0.1;

            const up = math.vec3.up();
            const yaw_angle = -hmov;
            const yaw_rotation = math.quat.fromAxis(yaw_angle, up);

            camera.angle = math.quat.mul(yaw_rotation, camera.angle);

            const right = math.quat.rotateVec(camera.angle, math.vec3.right());

            var new_pitch = camera.pitch + vmov;
            new_pitch = std.math.clamp(new_pitch, camera.pitch_min, camera.pitch_max);

            const pitch_delta = new_pitch - camera.pitch;
            camera.pitch = new_pitch;

            const pitch_rotation = math.quat.fromAxis(pitch_delta, right);
            camera.angle = math.quat.mul(pitch_rotation, camera.angle);
            camera.angle = camera.angle.norm();

            transform.view = camera.get_view();
        }

        if (input.action_just_pressed(.Pause)) {
            break :app;
        }

        const index: usize = @intFromBool(input.action_pressed(.Jump));

        transform.model = math.mat4.identity();

        var renderPass = try pipeline.begin(.{ .colorOp = .{ .Clear = .{ 0.0, 0.0, 0.0, 1.0 } }, .depthOp = .{ .Clear = .{ 0.0, 0.0, 0.0, 0.0 } } }, null);
        pipeline.bind_uniform_buffer(renderPass, &color, @sizeOf(UniformColor), .Fragment, 0);
        pipeline.bind_uniform_buffer(renderPass, &transform, @sizeOf(UniformTransform), .Vertex, 0);
        try pipeline.bind_texture(&renderPass, textures[index]);
        pipeline.bind_vertex_buffer(&renderPass, gpuBuffer);

        transform.model = transform.model.scale(math.vec3.set(10));
        pipeline.bind_uniform_buffer(renderPass, &transform, @sizeOf(UniformTransform), .Vertex, 0);
        try pipeline.bind_texture(&renderPass, textures[1]);
        pipeline.bind_vertex_buffer(&renderPass, cube);

        //try ui.begin_ui_pass(renderPass);

        try pipeline.end(&renderPass);

        var uirp = try ui.pipeline.begin(.{ .colorOp = .Load, .depthOp = null }, renderPass);

        try ui.debug_render_string_fmt(&uirp, 0, 0, math.vec4.one(), "FrameTime: {} - Pitch: {}", .{ dt, camera.pitch });

        try ui.pipeline.end(&uirp);
    }
}
// TODO: Scene
// TODO: Test Camera (formaize camera)
// TODO: multi-thread asset loading
// TODO: Sound asset type
// TODO: Level Layout asset type
// TODO: Collisions
