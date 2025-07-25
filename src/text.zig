const std = @import("std");
const assets = @import("assets.zig");
const host = @import("host.zig");
const sdl = host.sdl;
const math = @import("math.zig");
const key_t = assets.SceneResources.key_t;

// have at least one langauge be included by default
// translations can be loaded as needed
const default_pack = @embedFile("embed/default.tlist");
const default_language = Languages.English;

pub inline fn string_is_empty_or_whitespace(string: []const u8) bool {
    return string.len == 0 or std.mem.trim(u8, string, &.{ ' ', '\t', '\n', '\r' }).len == 0;
}

pub fn string_to_cstr(allocator: std.mem.Allocator, string: []const u8) ![:0]u8 {
    const buffer = try allocator.allocSentinel(u8, string.len, 0);
    @memcpy(buffer[0..string.len], string);
    return buffer;
}

pub const Languages = enum(u32) {
    pub const Default = default_language;

    English,
    Portuguese,
};

pub const TextID = enum(u32) {
    n0,
    n1,
    n2,
    n3,
    n4,
    n5,
    n6,
    n7,
    n8,
    n9,
    e,
    nneg,
    ndec,
    Title,
    HelloWorld,
    LanguageName,
    _EOF_,
};

pub const Dim = struct {
    width: f32,
    height: f32,
};

pub const LanguagePack = struct {
    const This = @This();

    const dyn_info = struct {
        dyn_key: []const u8,
        size: Dim,
    };

    parent: *assets.SceneResources,
    font_name: []const u8,
    cache_textures: [@intFromEnum(TextID._EOF_)]?[]const u8,
    dyn_cache: std.StringHashMap(dyn_info),
    cache_infos: [@intFromEnum(TextID._EOF_)]?Dim,
    strings: []?[:0]u8,
    current_language: Languages,

    pub fn init(parent: *assets.SceneResources, fontName: []const u8) !This {
        const strings = try parse_text_list(parent.allocator, default_pack);

        return This{
            .parent = parent,
            .font_name = fontName,
            .strings = strings,
            .current_language = default_language,
            .cache_textures = [_]?[]const u8{null} ** @intFromEnum(TextID._EOF_),
            .cache_infos = [_]?Dim{null} ** @intFromEnum(TextID._EOF_),
            .dyn_cache = std.StringHashMap(dyn_info).init(parent.allocator),
        };
    }

    pub fn deinit(this: *This) void {
        this.clear_cache();
        this.dyn_cache.deinit();
    }

    pub fn gen_textures(this: *This) !void {
        //TODO: THIS NEEDS TO BE SERIOUSLY REFACTORED
        // TO DO THIS IN A SINGLE COPY PASS OR EVEN RETHOUGHT ON HOW TO
        // DO THIS WITHOUT FLOODING THE CACHE. THIS IS THE **TEMPORARY**
        // SOLUTION SO I CAN GET THINGS WORKING!!!
        inline for (@typeInfo(TextID).@"enum".fields) |field| {
            if (std.mem.eql(u8, field.name, "_EOF_")) break;

            _ = try this.get_texture(@enumFromInt(field.value));
        }
    }

    fn gen_dyn_key(allocator: std.mem.Allocator, string: []const u8) ![]u8 {
        const dyn_key_append = "__DYN_TXT_";
        const buffer = try allocator.alloc(u8, dyn_key_append.len + string.len);

        @memcpy(buffer[0..dyn_key_append.len], dyn_key_append);
        @memcpy(buffer[dyn_key_append.len..], string);

        return buffer;
    }

    pub fn get_texture_dyn(this: *This, string: []const u8) !?assets.GPUTexture {
        if (this.dyn_cache.get(string)) |dyn_key| {
            return this.parent.get(assets.GPUTexture, dyn_key.dyn_key).?;
        }

        const dyn_key = try gen_dyn_key(this.parent.allocator, string);
        errdefer this.parent.allocator.free(dyn_key);

        const texture = try this.gen_texture_dyn(string) orelse return null;
        _ = try this.parent.insert_resource(assets.GPUTexture, texture.texture, dyn_key, .{ .gpu_texture = .{} });
        errdefer this.parent.free_resource(dyn_key);

        try this.dyn_cache.put(string, dyn_info{
            .dyn_key = dyn_key,
            .size = Dim{
                .width = texture.width,
                .height = texture.height,
            },
        });
        // I think that this get_texture_dyn/gen is done, but will need to test still.
        // todo: add debug_render_text_fmt method. Note that there is still the issue that a copyPass cannot
        // happen in the middle of a renderPass so we'll probably need to introduce a prepare_debug_text_fmt
        // method to prepare the non-number elements of the format string outside of the renderPass
        return texture.texture;
    }

    pub fn get_texture(this: *This, id: TextID) !assets.GPUTexture {
        if (this.cache_textures[@intFromEnum(id)]) |key| {
            return this.parent.get(assets.GPUTexture, key).?;
        }
        const texture = try this.gen_texture(id);

        const pseudo_key = this.parent.next_key();
        const buffer = try std.fmt.allocPrint(this.parent.allocator, "CACHED-TEXT-{d}", .{pseudo_key});
        errdefer this.parent.allocator.free(buffer);

        _ = try this.parent.insert_resource(assets.GPUTexture, texture.texture, buffer, .{ .gpu_texture = .{} });

        this.cache_textures[@intFromEnum(id)] = buffer;
        this.cache_infos[@intFromEnum(id)] = .{
            .width = texture.width,
            .height = texture.height,
        };

        return texture.texture;
    }

    pub fn get_texture_size_dyn(this: *This, string: []const u8) !Dim {
        if (this.dyn_cache.get(string)) |info| {
            return info.size;
        }
        _ = try this.get_texture_dyn(string);
        return if (this.dyn_cache.get(string)) |info| info.size else .{ .width = 0, .height = 0 };
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

    fn gen_texture_dyn(this: *This, string: []const u8) !?TexInfo {
        if (string_is_empty_or_whitespace(string)) {
            return null;
        }

        const font = this.parent.get_ptr(assets.Font, this.font_name) orelse return error.FontNotFound;
        std.debug.assert(font.handle != null);

        const cstr = try string_to_cstr(this.parent.allocator, string);
        defer this.parent.allocator.free(cstr);

        return try gen_surface_font(font, cstr);
    }

    fn gen_texture(this: *This, id: TextID) !TexInfo {
        const idx: usize = @intFromEnum(id);
        std.debug.assert(idx < this.strings.len);

        const font = this.parent.get_ptr(assets.Font, this.font_name) orelse return error.FontNotFound;
        const string = this.strings[idx] orelse "UNDEFINED";

        std.debug.assert(font.handle != null);

        return try gen_surface_font(font, string);
    }

    fn gen_surface_font(font: *assets.Font, string: [:0]const u8) !TexInfo {
        //BLENDED => RGBA32
        //Solid => Mono8
        // TODO: Add fast/fancy text rendering (solid is faster)
        // now that we've solved the texture issue (the currently accepted solution)
        // which coppies by rows and factors in pitch should now work for either.
        // Note that the shader will need a tag to know whether or not to load from r or a channel
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
            return host.sdl_debug_error("Text Render");
        }
        defer sdl.SDL_DestroySurface(surface);

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
                .texture_name = string.ptr,
                .format = .RGBA32,
            },
            .usage = .Sampler,
        };
        var stage = try host.begin_stage_buffer(textureInfo);
        const buffer = try host.map_stage_buffer(u8, stage);

        var src_ptr: [*]u8 = @ptrCast(@alignCast(surface.*.pixels));
        var dst_ptr: [*]u8 = buffer;

        for (0..@as(usize, @intCast(surface.*.h))) |_| {
            const span: usize = @intCast(surface.*.w * pixelInfo.*.bytes_per_pixel);

            @memcpy(dst_ptr[0..span], src_ptr[0..span]);
            src_ptr += @as(usize, @intCast(surface.*.pitch));
            dst_ptr += span;
        }

        const texture = (try host.submit_stage_buffer(host.GPUTexture, &stage, null)).?;

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
            defer this.parent.allocator.free(strings);
            this.update_strings(strings);
            return;
        }

        const info = @typeInfo(Languages);
        var filenames: [info.@"enum".fields.len][]const u8 = undefined;

        inline for (info.@"enum".fields, 0..) |field, i| {
            filenames[i] = "locale/" ++ field.name ++ ".tlist";
        }

        const language_name = filenames[@intFromEnum(language)];

        const language_dat = try assets.read_file(this.parent.allocator, language_name);
        defer this.parent.allocator.free(language_dat);

        const language_strings = try parse_text_list(this.parent.allocator, language_dat);
        defer this.parent.allocator.free(language_strings);

        this.update_strings(language_strings);
    }

    fn update_strings(this: *This, new_pack: []const ?[:0]u8) void {
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
        var iter = this.dyn_cache.iterator();
        while (iter.next()) |entry| {
            this.parent.free_resource(entry.value_ptr.dyn_key);
            this.parent.allocator.free(entry.key_ptr.*);
        }
        this.dyn_cache.clearAndFree();
    }

    fn parse_text_list(allocator: std.mem.Allocator, data: []const u8) ![]?[:0]u8 {
        const max_text_idx: u32 = @intFromEnum(TextID._EOF_);
        var buffer = try allocator.alloc(?[:0]u8, max_text_idx);
        errdefer allocator.free(buffer);

        var lines = std.mem.splitAny(u8, data, "\n");
        var index: usize = 0;
        while (lines.next()) |line| : (index += 1) {
            if (line.len == 0) break;

            buffer[index] = try allocator.allocSentinel(u8, line.len, 0);
            errdefer allocator.free(buffer[index]);
            @memcpy(buffer[index].?[0..line.len], line);
        }

        return buffer;
    }
};
