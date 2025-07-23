const std = @import("std");
const assets = @import("assets.zig");
const host = @import("host.zig");
const sdl = host.sdl;
const math = @import("math.zig");
const key_t = assets.SceneResources.key_t;

// have at least one langauge be included by default
// translations can be loaded as needed
const default_pack = @embedFile("../zig-out/bin/assets//locale/default.tlist");
const default_language = Languages.English;

pub const Languages = enum(u32) {
    pub const Default = default_language;

    English,
};

pub const TextID = enum(u32) {
    Title,
    HelloWorld,
    _EOF_,
};

pub const Dim = struct {
    width: f32,
    height: f32,
};

pub const LanguagePack = struct {
    const This = @This();

    parent: *assets.SceneResources,
    font_name: []const u8,
    cache_textures: [@intFromEnum(TextID._EOF_)]?[]u8,
    cache_infos: [@intFromEnum(TextID._EOF_)]?Dim,
    strings: []?[:0]const u8,
    current_language: Languages,

    pub fn init(parent: *assets.SceneResources, fontName: []const u8) !This {
        const strings = try parse_text_list(parent.allocator, default_pack);

        return This{
            .parent = parent,
            .font_name = fontName,
            .strings = strings,
            .current_langauge = default_language,
            .cache_textures = [_]?key_t{null} ** @intFromEnum(TextID._EOF_),
        };
    }

    pub fn deinit(this: *This) void {
        this.clear_cache();
    }

    pub fn get_texture(this: *This, id: TextID) !assets.GPUTexture {
        if (this.cache_textures[@intFromEnum(id)]) |key| {
            return this.parent.get(assets.GPUTexture, key);
        }
        const texture = try this.gen_texture(id);

        const pseudo_key = this.parent.next_key();
        const buffer = try std.fmt.allocPrint(this.parent.allocator, "CACHED-TEXT-{d}", .{pseudo_key});

        this.parent.insert_resource(assets.GPUTexture, texture.texture, buffer, .{ .gpu_texture = .{} });

        this.cache_textures[@intFromEnum(id)] = buffer;
        this.cache_infos[@intFromEnum(id)] = .{
            .width = texture.width,
            .height = texture.height,
        };

        return texture;
    }

    pub fn get_texture_size(this: *This, id: TextID) !Dim {
        if (this.cache_infos[@intFromEnum(id)]) |info| {
            return info;
        }

        _ = try this.get_texture(id);
        return this.cache_infos[@intFromEnum(id)] orelse unreachable;
    }

    const TexInfo = struct {
        texture: assets.GPUTexture,
        width: f32,
        height: f32,
    };

    fn gen_texture(this: *This, id: TextID) !TexInfo {
        const idx: usize = @intFromEnum(id);
        std.debug.assert(idx < this.strings.len);

        const font = this.parent.get_ptr(assets.Font, this.font_name) orelse return error.FontNotFound;

        const string = this.strings[idx] orelse "UNDEFINED";
        const surface = sdl.TTF_RenderText_Blended(
            font.handle,
            string.ptr,
            string.len,
            sdl.SDL_Color{
                .r = 255,
                .g = 255,
                .b = 255,
                .a = 255,
            },
        );

        if (surface == null) {
            return error.TextRenderError;
        }
        defer sdl.SDL_DestroySurface(surface);

        // surfaces that are returned from TTL_RenderText apparently are lawyas in RGBA or SDL_PIXELFORMAT_RGBA32 format
        std.debug.assert(surface.*.format == sdl.SDL_PIXELFORMAT_RGBA32);

        const pixelInfo = sdl.SDL_GetPixelFormatDetails(surface.*.format);

        // upload to gpu directly (done to avoid a bunch of resource insertion and sequential removing from the scene resources)
        const textureInfo = host.BufferCreateInfo{
            .dynamic_upload = false, // Maybe this is a case where it would be beneficial to set this to true...
            .element_size = undefined,
            .num_elements = undefined,
            .texture_info = .{
                .width = @intCast(surface.*.w),
                .height = @intCast(surface.*.h),
                .address_policy = .Clamp,
                .min_filter = .Nearest,
                .mag_filter = .Nearest,
                .enable_mipmaps = false,
                .mipmap_filter = .Nearest,
                .texture_name = string[0..string.len],
            },
            .usage = .Sampler,
        };
        const stage = try host.begin_stage_buffer(textureInfo);
        const buffer = try host.map_stage_buffer(u8, stage);

        const len = @as(usize, @intCast(surface.*.w * surface.*.h * pixelInfo.*.bytes_per_pixel));
        const view = buffer[0..len];
        @memcpy(view, @as([*]const u8, @ptrCast(@alignCast(surface.*.pixels)))[0..len]);

        const texture = try host.submit_stage_buffer(host.GPUTexture, stage, null);

        return .{
            .texture = texture,
            .width = @floatFromInt(surface.*.w),
            .height = @floatFromInt(surface.*.h),
        };
    }

    pub fn load_translation_pack(this: *This, language: Languages) !void {
        // load langauge pack over top of default english pack replacing entries
        // any missing entries in translation should keep english text.
        this.current_language = language;

        if (language == default_language) {
            const strings = try parse_text_list(this.parent.allocator, default_pack);
            this.update_strings(strings);
            return;
        }

        return error.NotImplemented;
    }

    fn update_strings(this: *This, new_pack: []const ?[]const u8) void {
        var any = false;
        for (0..this.strings.len) |lineno| {
            if (new_pack[lineno] == null) continue;

            if (this.strings[lineno]) |span| {
                this.parent.allocator.free(span);
            }
            this.strings[lineno] = new_pack[lineno];
            any = true;
        }

        if (any) {
            this.clear_cache();
        }
    }

    pub fn clear_cache(this: *This) void {
        for (0..@intFromEnum(TextID._EOF_)) |idx| {
            if (this.cache_textures[idx]) |pkey| {
                this.parent.free_resource(pkey);
                this.parent.allocator.free(pkey);
                this.cache_textures[idx] = null;
            }
            this.cache_infos[idx] = null;
        }
    }

    fn parse_text_list(allocator: std.mem.Allocator, data: []const u8) ![]?[:0]const u8 {
        const max_text_idx: u32 = @intFromEnum(TextID._EOF_);
        const buffer = try allocator.alloc([]const u8, max_text_idx);
        errdefer allocator.free(buffer);

        var lines = std.mem.splitAny(u8, data, "\n");
        var index: usize = 0;
        while (lines.next()) |line| : (index += 1) {
            buffer[index] = try allocator.allocSentinel(u8, line.len, 0);
            errdefer allocator.free(buffer[index]);
            @memcpy(buffer[index][0..line.len], line);
        }

        return error.NotImplemented;
    }
};

// pub const TextRendererConfig = struct {
//     ortho_view: struct {
//         x: f32,
//         y: f32,
//         width: f32,
//         height: f32,
//         near: f32,
//         far: f32,
//     },
//     language: LanguagePack,
// };

// pub const TextRenderer = struct {
//     const This = @This();

//     parent: *assets.SceneResources,
//     projection: math.mat4,

//     pub fn init(config: TextRendererConfig, parent: *assets.SceneResources) This {}
// };
