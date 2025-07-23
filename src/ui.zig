const host = @import("host.zig");
const assets = @import("assets.zig");
const text = @import("text.zig");
const math = @import("math.zig");
const std = @import("std");
const sdl = host.sdl;

const This = @This();

projection: math.mat4,
camera: math.mat4,
scene: *assets.SceneResources,
language_pack: text.LanguagePack,
pipeline: host.Pipeline,
render_pass: ?host.Pipeline.RenderPass,

const TextUniform = extern struct {
    projection: math.mat4,
    camera: math.mat4,
    model: math.mat4,
};

/// font is just the asset-name and needs to have already been loaded in the sceneResources
pub fn init(display_width: f32, display_height: f32, zNear: f32, zFar: f32, scene: *assets.SceneResources, font: []const u8, language: text.Languages) This {
    var language_pack = text.LanguagePack.init(scene, font) catch unreachable; // unreachable because it means that not even the default language could be loaded

    if (language != text.Languages.Default) {
        language_pack.load_translation_pack(language) catch {
            std.debug.print("Unable to load language pack: {}, default {} will be used.\n", .{ language, text.Languages.Default });
        };
    }

    scene.assert_asset_exists(assets.Shader, assets.Default.TextVertexShader);
    scene.assert_asset_exists(assets.Shader, assets.Default.TextFragmentShader);
    scene.assert_asset_exists(host.GPUBuffer, assets.Default.Quad);

    // TODO: Build pipeline
    // TODO: Text render shaders
    // TODO: quad render helper (also for text rendering)
    // TODO: interface
    // TODO: test
    // TODO: Other 2d primitives

    return This{
        .projection = math.mat4.orthographic(0, display_width, display_height, 0, zNear, zFar),
        .camera = math.mat4.identity(),
        .scene = scene,
        .language_pack = language,
    };
}

pub fn deinit(this: *This) void {
    this.language_pack.deinit();
}

pub fn begin_ui_pass(this: *This) !void {
    std.debug.assert(this.render_pass == null);

    //this.render_pass = this.pipeline.begin()

}
