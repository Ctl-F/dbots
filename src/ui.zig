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

pub fn render_number(this: *This, renderPass: ?*RenderPass, value: f64, x: f32, y: f32, anchor: Anchor, blend: ?math.vec4) !text.Dim {
    var cursor_x = x;
    var height: f32 = 0;
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

        height = @max(height, size.height);

        if (renderPass) |pass| {
            try render_quad_anchor(this, pass, cursor_x, y, size.width, size.height, anchor, blend, texture);
        }
        cursor_x += size.width;
    }

    return .{ .width = cursor_x - x, .height = height };
}

pub fn debug_render_string(this: *This, renderPass: ?*RenderPass, string: []const u8, x: f32, y: f32, blend: ?math.vec4) !text.Dim {
    const texture = (try this.language_pack.get_texture_dyn(string)) orelse return std.mem.zeroes(text.Dim);
    const size = try this.language_pack.get_texture_size_dyn(string);

    if (renderPass) |rp| {
        try render_quad_anchor(this, rp, x, y, size.width, size.height, .TopLeft, blend, texture);
    }

    return size;
}

pub fn debug_render_string_fmt(
    this: *This,
    renderPass: ?*RenderPass,
    x: f32,
    y: f32,
    blend: ?math.vec4,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    // stolen logic from std.fmt.format
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or string argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.@"struct".fields;
    if (fields_info.len > 32) {
        @compileError("32 arguments max are supported per format call");
    }

    var cursor_x = x;
    var cursor_y = y;
    cursor_y += 0; // TODO

    @setEvalBranchQuota(2000000);
    //comptime var arg_state: std.fmt.ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    comptime var literal: []const u8 = "";
    comptime var arg_idx = 0;
    inline while (true) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescaped_brace = false;

        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescaped_brace = true;
            end_index += 1;
            i += 2;
        }

        literal = literal ++ fmt[start_index..end_index];

        if (unescaped_brace) continue;

        if (literal.len != 0) {
            //TODO: split newline

            const size = try debug_render_string(this, renderPass, literal, cursor_x, cursor_y, blend);

            cursor_x += size.width;
            literal = "";
        }

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        comptime std.debug.assert(fmt[i] == '{');
        i += 1;

        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        comptime std.debug.assert(fmt[i] == '}');
        i += 1;

        const arg_to_print = arg_idx;
        arg_idx += 1;

        if (fields_info.len <= arg_to_print) {
            @compileError("too few arguments - " ++
                std.fmt.comptimePrint("{d}", .{arg_to_print}) ++
                " / " ++ std.fmt.comptimePrint("{d}", .{fields_info.len}));
        }

        //comptime arg_state.nextArg(null) orelse @compileError("too few arguments");
        const arg = @field(args, fields_info[arg_to_print].name);

        const value: f64 = switch (@TypeOf(arg)) {
            f32, comptime_float => @floatCast(arg),
            f64 => arg,
            i32, i64, u32, u64, u8, comptime_int => @floatFromInt(arg),
            else => @compileError("Unsupported argument type."),
        };

        const size = try render_number(this, renderPass, value, cursor_x, cursor_y, .TopLeft, blend);
        cursor_x += size.width;
    }

    if (arg_idx < fields_info.len) {
        const missing_count = arg_idx - fields_info.len;
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("Unused argument in '" ++ fmt ++ "'"),
            else => @compileError(std.fmt.comptimePrint("{d}", .{missing_count}) ++ " unused argument in '" ++ fmt ++ "'"),
        }
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
