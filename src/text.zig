const std = @import("std");
const assets = @import("assets.zig");

const key_t = assets.SceneResources.key_t;

// have at least one langauge be included by default
// translations can be loaded as needed
const default_pack = @embedFile("../zig-out/bin/assets//locale/default.tlist");
const default_language = Languages.English;

pub const Languages = enum(u32) {
    English,
};

pub const TextID = enum(u32) {
    Title,
    HelloWorld,
    _EOF_,
};

pub const LanguagePack = struct {
    const This = @This();

    parent: *assets.SceneResources,
    font_name: []const u8,
    cache_textures: [@intFromEnum(TextID._EOF_)]?key_t,
    strings: []?[]const u8,
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

    pub fn get_texture(this: *This, id: TextID) !assets.GPUTexture {
        if (this.cache_textures[@intFromEnum(id)]) |key| {
            return this.parent.get(assets.GPUTexture, key);
        }
        return this.gen_texture(id);
    }

    fn gen_texture(this: *This, id: TextID) !assets.GPUTexture {
        _ = this;
        _ = id; // todo impl
        return error.NotImplemented;
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
                const node = this.parent.get_lookup_node_by_index(pkey) orelse unreachable;
                this.parent.free_resource_direct(node);
                this.cache_textures[idx] = null;
            }
        }
    }

    fn parse_text_list(allocator: std.mem.Allocator, data: []const u8) ![]?[]const u8 {
        const max_text_idx: u32 = @intFromEnum(TextID._EOF_);
        const buffer = try allocator.alloc([]const u8, max_text_idx);
        errdefer allocator.free(buffer);

        var lines = std.mem.splitAny(u8, data, "\n");
        var index: usize = 0;
        while (lines.next()) |line| : (index += 1) {
            buffer[index] = try allocator.alloc(u8, line.len);
            errdefer allocator.free(buffer[index]);
            @memcpy(buffer[index], line);
        }

        return error.NotImplemented;
    }
};
