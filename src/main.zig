const std = @import("std");
const host = @import("host.zig");
const assets = @import("assets.zig");
const math = @import("math.zig");
const UI = @import("ui.zig");

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
        .display = .{ .width = 1280, .height = 800, .monitor = null },
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
                .font = .{ .size = 48 },
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

        copyPass.claim_ownership_of_results();
    }

    // we don't need to release the texture anymore becauser it's now owned by the scene.
    //const texture = scene.get(host.GPUTexture, "gpu_dragon_eye") orelse unreachable;

    const textures = [_]host.GPUTexture{
        scene.get(host.GPUTexture, "gpu_dragon_eye") orelse unreachable,
        scene.get(host.GPUTexture, assets.Default.CheckerBoard) orelse unreachable,
    };

    // const quad = scene.get(host.GPUBuffer, assets.Default.Quad) orelse unreachable;
    // const quad_transform = math.mat4.mul(math.mat4.fromTranslate(math.vec3.new(40, 40, 0)), math.mat4.fromScale(math.vec3.new(64, 64, 1)));

    const gpuBuffer = scene.get(host.GPUBuffer, "floor") orelse unreachable;

    scene.free_resource("basic_vert");
    scene.free_resource("basic_frag");

    var color: UniformColor = .{ .color = @splat(1) };
    var transform: UniformTransform = .{
        .projection = math.mat4.perspectiveReversedZ(90.0, @as(f32, @floatFromInt(options.display.width)) / @as(f32, @floatFromInt(options.display.height)), 0.01),
        .view = math.mat4.lookAt(math.vec3.new(0, 2, 3), math.vec3.zero(), math.vec3.up()),
        .model = math.mat4.identity(),
        .magic_id = 42,
    };

    // var uni_transform: UniformTransform = .{
    //     .projection = math.mat4.orthographic(0, @floatFromInt(options.display.width), @floatFromInt(options.display.height), 0, 0.01, 1),
    //     .view = math.mat4.fromTranslate(math.vec3.new(0, 0, 1)),
    //     .model = quad_transform,
    //     .magic_id = 65535,
    // };

    host.input_mode(.Keyboard);
    var input = host.input();

    var angle_x: f32 = 0;
    var angle_y: f32 = 0;

    var ui = try UI.init(@floatFromInt(options.display.width), @floatFromInt(options.display.height), 0.01, 100.0, &scene, "main_font", .English);

    //***TEMPORARY***
    try ui.language_pack.gen_textures();

    std.debug.print("Starting main loop\n", .{});
    app: while (!input.should_close()) {
        input.process_events();

        angle_y += input.mouse_x_rel * 0.01;
        angle_x -= input.mouse_y_rel * 0.01;

        transform.view = math.mat4.lookAt(math.vec3.new(0, 1, -3), math.vec3.zero(), math.vec3.up());

        if (input.action_just_pressed(.Pause)) {
            break :app;
        }

        const index: usize = @intFromBool(input.action_pressed(.Jump));

        var renderPass = try pipeline.begin(.{ .Clear = .{ 0.0, 0.0, 0.0, 1.0 } }, .{ .Clear = undefined }, null);
        pipeline.bind_uniform_buffer(renderPass, &color, @sizeOf(UniformColor), .Fragment, 0);
        pipeline.bind_uniform_buffer(renderPass, &transform, @sizeOf(UniformTransform), .Vertex, 0);
        try pipeline.bind_texture(&renderPass, textures[index]);
        pipeline.bind_vertex_buffer(&renderPass, gpuBuffer);

        // pipeline.bind_uniform_buffer(renderPass, &uni_transform, @sizeOf(UniformTransform), .Vertex, 0);
        // try pipeline.bind_texture(&renderPass, textures[1]);
        // pipeline.bind_vertex_buffer(&renderPass, quad);

        try ui.begin_ui_pass(renderPass);

        try ui.render_text(&renderPass, .HelloWorld, 10, 10, math.vec4.one());
        try ui.render_quad(&renderPass, 100, 100, 16, 16, math.vec4.one(), null);

        try ui.render_text_aligned(&renderPass, .Title, @floatFromInt(options.display.width / 2), 10, .TopCenter, math.vec4.new(1, 0, 0, 1));

        try pipeline.end(renderPass);
    }
}

// TODO: Finish text rendering
// TODO: Test Camera (formaize camera)

// TODO: multi-thread asset loading
// TODO: Sound asset type
// TODO: Level Layout asset type
// TODO: Collisions
// TODO: Text rendering
