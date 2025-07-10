const std = @import("std");
const host = @import("host.zig");
const assets = @import("assets.zig");

const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    g: f32,
    b: f32,
    u: f32,
    v: f32,
};

fn upload_sprite(sprite: assets.SoftwareTexture) !host.GPUTexture {
    const config = host.BufferCreateInfo{
        .dynamic_upload = false,
        .element_size = undefined,
        .num_elements = undefined,
        .texture_info = .{
            .address_policy = .Repeat,
            .enable_mipmaps = false,
            .width = @intCast(sprite.width),
            .height = @intCast(sprite.height),
            .mag_filter = .Nearest,
            .min_filter = .Nearest,
            .mipmap_filter = .Nearest,
            .texture_name = "Dragon Eye",
        },
        .usage = .Sampler,
    };
    var stage = try host.begin_stage_buffer(config);
    const buffer = try host.map_stage_buffer(u8, stage);

    const size: usize = @intCast(sprite.width * sprite.height * sprite.bytes_per_pixel);
    const view = buffer[0..size];
    @memcpy(view, @as([*c]const u8, @ptrCast(@alignCast(sprite.pixels)))[0..size]);

    return try host.submit_stage_buffer(host.GPUTexture, &stage);
}

fn get_triangle_buffer(format: host.VertexFormat) !host.GPUBuffer {
    const triangle = [_]Vertex{
        .{ .x = -0.75, .y = -0.75, .z = 0, .r = 0.3, .g = 0, .b = 0.3, .u = 0.0, .v = 0.0 },
        .{ .x = 0.75, .y = -0.75, .z = 0, .r = 0.3, .g = 0, .b = 0.3, .u = 1.0, .v = 0.0 },
        .{ .x = -0.75, .y = 0, .z = 0, .r = 0, .g = 0, .b = 0.3, .u = 0.0, .v = 1.0 },

        .{ .x = -0.75, .y = 0, .z = 0, .r = 0, .g = 0, .b = 0.3, .u = 0.0, .v = 1.0 },
        .{ .x = 0.75, .y = 0, .z = 0, .r = 0, .g = 0, .b = 0.3, .u = 1.0, .v = 1.0 },
        .{ .x = 0.75, .y = -0.75, .z = 0, .r = 0.3, .g = 0, .b = 0.3, .u = 1.0, .v = 0.0 },

        .{ .x = -0.75, .y = 0.75, .z = 0, .r = 0, .g = 0.3, .b = 0.2, .u = 0.0, .v = 0.0 },
        .{ .x = 0.75, .y = 0.75, .z = 0, .r = 0, .g = 0.3, .b = 0.2, .u = 0.0, .v = 0.0 },
        .{ .x = -0.75, .y = 0, .z = 0, .r = 0, .g = 0, .b = 0.3, .u = 0.0, .v = 0.0 },

        .{ .x = -0.75, .y = 0, .z = 0, .r = 0, .g = 0, .b = 0.3, .u = 0.0, .v = 0.0 },
        .{ .x = 0.75, .y = 0.75, .z = 0, .r = 0, .g = 0.3, .b = 0.2, .u = 0.0, .v = 0.0 },
        .{ .x = 0.75, .y = 0, .z = 0, .r = 0, .g = 0, .b = 0.3, .u = 0.0, .v = 0.0 },
    };

    var stagingInfo = try host.begin_stage_buffer(host.BufferCreateInfo{
        .usage = .Vertex,
        .element_size = format.stride,
        .num_elements = triangle.len,
        .dynamic_upload = false,
        .texture_info = null,
    });

    var stagingBuffer = try host.map_stage_buffer(Vertex, stagingInfo);

    @memcpy(stagingBuffer[0..triangle.len], triangle[0..]);

    return try host.submit_stage_buffer(host.GPUBuffer, &stagingInfo);
}

const UniformColor = extern struct {
    color: [4]f32,
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
                        .uniform_buffer_count = 0,
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
    });

    var vertexFormat = host.VertexFormat.begin();
    try vertexFormat.add(.Float3);
    try vertexFormat.add(.Float3);
    try vertexFormat.add(.Float2);

    vertexFormat.display_format();

    const pipelineInfo = host.PipelineConfig{
        .vertex_shader = scene.get(assets.Shader, "basic_vert") orelse unreachable,
        .fragment_shader = scene.get(assets.Shader, "basic_frag") orelse unreachable,
        .topology = .TriangleList,
        .vertex_format = vertexFormat,
        .enable_depth_buffer = true,
        .enable_culling = false,
    };
    const pipeline = try host.Pipeline.init(pipelineInfo);
    defer pipeline.free();

    const gpuBuffer = try get_triangle_buffer(vertexFormat);
    defer gpuBuffer.release();

    const texture = try upload_sprite(scene.get(assets.SoftwareTexture, "dragon_eye") orelse unreachable);

    scene.free_resource("basic_vert");
    scene.free_resource("basic_frag");

    std.debug.print("Starting main loop\n", .{});

    var color: UniformColor = .{ .color = @splat(1) };

    app: while (true) {
        var event: host.sdl.SDL_Event = undefined;
        while (host.sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                host.sdl.SDL_EVENT_QUIT => break :app,
                host.sdl.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == host.sdl.SDL_SCANCODE_ESCAPE) {
                        break :app;
                    }

                    const debug_print = A: {
                        if (event.key.scancode == host.sdl.SDL_SCANCODE_1) {
                            color.color[0] = 1.0 - color.color[0];
                            break :A true;
                        } else if (event.key.scancode == host.sdl.SDL_SCANCODE_2) {
                            color.color[1] = 1.0 - color.color[1];
                            break :A true;
                        } else if (event.key.scancode == host.sdl.SDL_SCANCODE_3) {
                            color.color[2] = 1.0 - color.color[2];
                            break :A true;
                        }

                        break :A false;
                    };

                    if (debug_print) {
                        std.debug.print("{},{},{}\n", .{ color.color[0], color.color[1], color.color[2] });
                    }
                },

                else => {},
            }
        }

        var renderPass = try pipeline.begin(.{ 0.0, 0.0, 0.0, 1.0 });
        pipeline.bind_uniform_buffer(renderPass, &color, @sizeOf(UniformColor), .Fragment, 0);
        try pipeline.bind_texture(&renderPass, texture);
        pipeline.bind_vertex_buffer(&renderPass, gpuBuffer);
        try pipeline.end(renderPass);
    }
}

// TODO: Bulk staging buffer uploading (single copyPass)
