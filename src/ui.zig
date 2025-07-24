const host = @import("host.zig");
const assets = @import("assets.zig");
const text = @import("text.zig");
const math = @import("math.zig");
const std = @import("std");
const sdl = host.sdl;

const This = @This();

const RenderPass = host.Pipeline.RenderPass;

projection: math.mat4,
camera: math.mat4,
scene: *assets.SceneResources,
language_pack: text.LanguagePack,
pipeline: host.Pipeline,

const TextTransformUniform = extern struct {
    projection: math.mat4,
    camera: math.mat4,
    model: math.mat4,
};
const TextColorUniform = extern struct {
    blend: math.vec4,
    show_texture: i32,
};

pub const Anchor = enum {
    TopLeft,
    TopCenter,
    TopRight,
    MiddleLeft,
    MiddleCenter,
    MiddleRight,
    BottomLeft,
    BottomCenter,
    BottomRight,

    fn transform(this: @This(), x: *f32, y: *f32, width: f32, height: f32) void {
        const hw = width * 0.5;
        const hh = height * 0.5;

        switch (this) {
            .TopLeft => {
                x.* = align_value(x.*, 1, hw);
                y.* = align_value(y.*, 1, hh);
            },
            .TopCenter => {
                y.* = align_value(y.*, 1, hh);
            },
            .TopRight => {
                x.* = align_value(x.*, -1, hw);
                y.* = align_value(y.*, 1, hh);
            },
            .MiddleLeft => {
                x.* = align_value(x.*, 1, hw);
            },
            .MiddleCenter => return,
            .MiddleRight => {
                x.* = align_value(x.*, -1, hw);
            },
            .BottomLeft => {
                x.* = align_value(x.*, 1, hw);
                y.* = align_value(y.*, -1, hh);
            },
            .BottomCenter => {
                y.* = align_value(y.*, -1, hh);
            },
            .BottomRight => {
                x.* = align_value(x.*, -1, hw);
                y.* = align_value(y.*, -1, hh);
            },
        }
    }

    inline fn align_value(value: f32, bias: f32, factor: f32) f32 {
        return value + bias * factor;
    }
};

/// font is just the asset-name and needs to have already been loaded in the sceneResources
pub fn init(display_width: f32, display_height: f32, zNear: f32, zFar: f32, scene: *assets.SceneResources, font: []const u8, language: text.Languages) !This {
    var language_pack = text.LanguagePack.init(scene, font) catch unreachable; // unreachable because it means that not even the default language could be loaded
    errdefer language_pack.deinit();

    if (language != text.Languages.Default) {
        language_pack.load_translation_pack(language) catch {
            std.debug.print("Unable to load language pack: {}, default {} will be used.\n", .{ language, text.Languages.Default });
        };
    }

    scene.assert_asset_exists(assets.Shader, assets.Default.TextVertexShader);
    scene.assert_asset_exists(assets.Shader, assets.Default.TextFragmentShader);
    scene.assert_asset_exists(host.GPUBuffer, assets.Default.Quad);

    var format = host.VertexFormat.begin();
    assets.Vertex.fmt(&format);

    const pipelineInfo = host.PipelineConfig{
        .enable_culling = false,
        .enable_depth_buffer = true,
        .fragment_shader = scene.get(assets.Shader, assets.Default.TextFragmentShader) orelse unreachable,
        .vertex_shader = scene.get(assets.Shader, assets.Default.TextVertexShader) orelse unreachable,
        .topology = .TriangleList,
        .vertex_format = format,
        .blend_mode = .Alpha,
    };

    // TODO: Build pipeline
    // TODO: Text render shaders
    // TODO: quad render helper (also for text rendering)
    // TODO: interface
    // TODO: test
    // TODO: Other 2d primitives

    const pipeline = try host.Pipeline.init(pipelineInfo);

    return This{
        .projection = math.mat4.orthographic(0, display_width, display_height, 0, zNear, zFar),
        .camera = math.mat4.fromTranslate(math.vec3.new(0, 0, 1)),
        .scene = scene,
        .language_pack = language_pack,
        .pipeline = pipeline,
    };
}

pub fn deinit(this: *This) void {
    this.pipeline.free();
    this.language_pack.deinit();
}

pub fn begin_ui_pass(this: *This, renderPass: RenderPass) !void {
    this.pipeline.use(renderPass);
}

//TODO: Render fmt???

var NUMBER_BUFFER = [_]u8{0} ** 512;

pub fn render_number(this: *This, renderPass: *RenderPass, value: f64, x: f32, y: f32, anchor: Anchor, blend: ?math.vec4) !void {
    var cursor_x = x;

    //TODO: fix right-aligned text

    const string = try std.fmt.bufPrint(&NUMBER_BUFFER, "{d:0>5.3}", .{value});

    for (string) |char| {
        const string_id: text.TextID = switch (char) {
            '0' => .n0,
            '1' => .n1,
            '2' => .n2,
            '3' => .n3,
            '4' => .n4,
            '5' => .n5,
            '6' => .n6,
            '7' => .n7,
            '8' => .n8,
            '9' => .n9,
            'e' => .e,
            '-' => .nneg,
            '.' => .ndec,
            else => {
                std.debug.print("Unreachable char: {}\n", .{char});
                unreachable;
            },
        };

        const texture = try this.language_pack.get_texture(string_id);
        const size = try this.language_pack.get_texture_size(string_id);

        try render_quad_anchor(this, renderPass, cursor_x, y, size.width, size.height, anchor, blend, texture);

        cursor_x += size.width;
    }
}

pub fn render_text(this: *This, renderPass: *RenderPass, string: text.TextID, x: f32, y: f32, blend: ?math.vec4) !void {
    const texture = try this.language_pack.get_texture(string);
    const size = try this.language_pack.get_texture_size(string);

    return render_quad_anchor(this, renderPass, x, y, size.width, size.height, .TopLeft, blend, texture);
}

pub fn render_text_aligned(this: *This, renderPass: *RenderPass, string: text.TextID, x: f32, y: f32, anchor: Anchor, blend: ?math.vec4) !void {
    const texture = try this.language_pack.get_texture(string);
    const size = try this.language_pack.get_texture_size(string);

    return render_quad_anchor(this, renderPass, x, y, size.width, size.height, anchor, blend, texture);
}

pub fn render_quad(this: *This, renderPass: *RenderPass, x: f32, y: f32, width: f32, height: f32, color: ?math.vec4, texture: ?host.GPUTexture) !void {
    return render_quad_anchor(this, renderPass, x, y, width, height, .MiddleCenter, color, texture);
}

pub fn render_quad_anchor(this: *This, renderPass: *RenderPass, x: f32, y: f32, width: f32, height: f32, anchor: Anchor, color: ?math.vec4, texture: ?host.GPUTexture) !void {
    var pos_x: f32 = x;
    var pos_y: f32 = y;
    anchor.transform(&pos_x, &pos_y, width, height);

    const transform = math.mat4.mul(
        math.mat4.fromTranslate(math.vec3.new(pos_x, pos_y, 0)),
        math.mat4.fromScale(math.vec3.new(width, height, 1)),
    );

    const uni_transform = TextTransformUniform{
        .projection = this.projection,
        .camera = this.camera,
        .model = transform,
    };
    const uni_blend = TextColorUniform{
        .blend = color orelse math.vec4.new(0, 0, 0, 1),
        .show_texture = @intFromBool(texture != null),
    };

    const tex = texture orelse this.scene.get(assets.GPUTexture, assets.Default.CheckerBoard) orelse unreachable;
    const quad = this.scene.get(assets.GPUBuffer, assets.Default.Quad) orelse unreachable;

    this.pipeline.bind_uniform_buffer(renderPass.*, &uni_transform, @sizeOf(TextTransformUniform), .Vertex, 0);
    this.pipeline.bind_uniform_buffer(renderPass.*, &uni_blend, @sizeOf(TextColorUniform), .Fragment, 0);
    try this.pipeline.bind_texture(renderPass, tex);
    this.pipeline.bind_vertex_buffer(renderPass, quad);
}
