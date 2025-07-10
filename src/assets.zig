const std = @import("std");
const host = @import("host.zig");
const sdl = host.sdl;

const stb = @cImport(@cInclude("stb_image.h"));

const Module = @This();

pub const ASSET_FOLDER = switch (@import("builtin").mode) {
    .Debug => "zig-out/bin/assets/",
    else => "assets/",
};

pub fn get_asset_path(allocator: std.mem.Allocator, asset: []const u8) ![]u8 {
    const cwd = std.fs.cwd();

    const base_path = try cwd.realpathAlloc(allocator, ASSET_FOLDER);
    defer allocator.free(base_path);

    const path = try std.fs.path.join(allocator, &.{ base_path, asset });

    return path;
}

pub fn get_asset_pathz(allocator: std.mem.Allocator, asset: []const u8) ![:0]u8 {
    const cwd = std.fs.cwd();

    const base_path = try cwd.realpathAlloc(allocator, ASSET_FOLDER);
    defer allocator.free(base_path);

    const pathz = try std.fs.path.joinZ(allocator, &.{ base_path, asset });

    return pathz;
}

pub fn read_file(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const path = try get_asset_path(allocator, filename);
    defer allocator.free(path);

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();

    return try file.readToEndAlloc(allocator, stat.size);
}

pub const Shader = struct {
    const This = @This();

    pub const Stage = enum {
        Vertex,
        Fragment,

        fn internal_stage(this: @This()) c_uint {
            return switch (this) {
                .Vertex => sdl.SDL_GPU_SHADERSTAGE_VERTEX,
                .Fragment => sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            };
        }
    };

    pub const ResourceConfig = struct {
        sampler_count: u32,
        uniform_buffer_count: u32,
        storage_buffer_count: u32,
        storage_texture_count: u32,
    };

    handle: ?*sdl.SDL_GPUShader,

    pub fn load(allocator: std.mem.Allocator, filename: []const u8, stage: Stage, resources: ResourceConfig) !This {
        const source = try read_file(allocator, filename);
        defer allocator.free(source);

        const backend_formats = sdl.SDL_GetGPUShaderFormats(host.device());

        const fmt, const entrypoint: [*c]const u8 = if (backend_formats & sdl.SDL_GPU_SHADERFORMAT_SPIRV != 0) res: {
            break :res .{ sdl.SDL_GPU_SHADERFORMAT_SPIRV, "main" };
        } else {
            unreachable;
        };

        const create_info = sdl.SDL_GPUShaderCreateInfo{
            .code = source.ptr,
            .code_size = source.len,
            .entrypoint = entrypoint,
            .format = fmt,
            .stage = stage.internal_stage(),
            .num_samplers = resources.sampler_count,
            .num_storage_buffers = resources.storage_buffer_count,
            .num_uniform_buffers = resources.uniform_buffer_count,
            .num_storage_textures = resources.storage_texture_count,
        };

        const shader = sdl.SDL_CreateGPUShader(host.device(), &create_info);
        if (shader) |handle| {
            return This{ .handle = handle };
        }

        return host.sdl_debug_error("Error loading shader.");
    }

    pub fn release(this: *This) void {
        if (this.handle) |handle| {
            sdl.SDL_ReleaseGPUShader(host.device(), handle);
            this.handle = null;
        }
    }
};

pub const SoftwareTexture = struct {
    const This = @This();

    width: u32,
    height: u32,
    pixels: []u8,
    bytes_per_pixel: u4,

    pub fn load(asset: []const u8, vflip: bool) !This {
        const allocator = host.MemAlloc;

        const path = try get_asset_pathz(allocator, asset);
        defer allocator.free(path);

        var x: c_int = undefined;
        var y: c_int = undefined;
        var n: c_int = undefined;

        stb.stbi_set_flip_vertically_on_load(@intFromBool(vflip));

        const pixels = stb.stbi_load(path.ptr, &x, &y, &n, 4);
        if (pixels == null) {
            return error.ImageLoadError;
        }

        defer stb.stbi_image_free(pixels);

        const buffer_size: usize = @intCast(x * y * 4);

        const zig_pixels = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(zig_pixels);

        @memcpy(zig_pixels, pixels[0..buffer_size]);

        return This{
            .width = @intCast(x),
            .height = @intCast(y),
            .bytes_per_pixel = 4,
            .pixels = zig_pixels,
        };
    }

    pub fn release(this: This) void {
        host.MemAlloc.free(this.pixels);
    }
};

pub const ResourceType = union(enum) {
    raw: Raw,
    shader: ShaderRes,
    texture: Texture,
    gpu_texture: GPUTexture,

    pub const Raw = struct {};
    pub const ShaderRes = struct {
        stage: Shader.Stage,
        resources: Shader.ResourceConfig,
    };
    pub const Texture = struct {
        vflip: bool,
    };
    pub const GPUTexture = struct {};
};

pub const ResourceRequest = struct {
    asset_name: []const u8, // name to be used in-engine
    asset_source: []const u8, // asset file path realtive to assets/ folder
    type: ResourceType, // type to load as
};

const ResourceLookupNode = struct {
    resource_name: []const u8,
    resource_type: ResourceType,
    index: usize,
};

pub const RawBuffer = struct {
    buffer: []u8,
};

pub const SceneResources = struct {
    const This = @This();

    lookup: std.StringHashMap(ResourceLookupNode),
    shaders: std.AutoHashMap(usize, Shader),
    texture_sources: std.AutoHashMap(usize, SoftwareTexture),
    textures: std.AutoHashMap(usize, host.GPUTexture),
    binaries: std.AutoHashMap(usize, RawBuffer),
    allocator: std.mem.Allocator,
    id_counter: usize,

    pub fn init(allocator: std.mem.Allocator) This {
        return This{
            .allocator = allocator,
            .lookup = std.StringHashMap(ResourceLookupNode).init(allocator),
            .shaders = std.AutoHashMap(usize, Shader).init(allocator),
            .texture_sources = std.AutoHashMap(usize, SoftwareTexture).init(allocator),
            .textures = std.AutoHashMap(usize, host.GPUTexture).init(allocator),
            .binaries = std.AutoHashMap(usize, RawBuffer).init(allocator),
            .id_counter = 0,
        };
    }

    pub fn load(this: *This, assets: []const ResourceRequest) !void {
        for (assets) |request| { // TODO: Multi-thead if assets.len is larger than a threshold
            try this.load_resource(request);
            errdefer this.free_resource(request.asset_name);
        }
    }

    pub fn get(this: *This, comptime T: type, key: []const u8) ?T {
        if (this.get_ptr(T, key)) |ptr| {
            return ptr.*;
        } else {
            return null;
        }
    }

    inline fn assert_valid_type(comptime T: type, resource_type: ResourceType) void {
        switch (resource_type) {
            .raw => if (T != RawBuffer) {
                std.debug.print("Incorrect resource type requested: {s} expected RawBuffer\n", .{@typeName(T)});
                unreachable;
            },
            .shader => if (T != Shader) {
                std.debug.print("Incorrect resource type requested: {s} expected Shader\n", .{@typeName(T)});
                unreachable;
            },
            .texture => if (T != SoftwareTexture) {
                std.debug.print("Incorrect resource type requested: {s} expected SoftwareTexture\n", .{@typeName(T)});
                unreachable;
            },
            .gpu_texture => if (T != host.GPUTexture) {
                std.debug.print("Incorrect resource type requested: {s} expected GPUTexture\n", .{@typeName(T)});
                unreachable;
            },
        }
    }

    pub fn get_ptr(this: *This, comptime T: type, key: []const u8) ?*T {
        const lookup = this.lookup.get(key) orelse return null;
        assert_valid_type(T, lookup.resource_type);

        return switch (T) {
            RawBuffer => this.binaries.getPtr(lookup.index),
            Shader => this.shaders.getPtr(lookup.index),
            SoftwareTexture => this.texture_sources.getPtr(lookup.index),
            host.GPUTexture => this.textures.getPtr(lookup.index),
            else => unreachable,
        };
    }

    fn load_resource(this: *This, request: ResourceRequest) !void {
        switch (request.type) {
            .raw => {
                return this.load_resource_raw(request);
            },
            .shader => |s| {
                return this.load_resource_shader(request, s);
            },
            .texture => |t| {
                return this.load_resource_texture(request, t);
            },
            .gpu_texture => {
                std.debug.print("GPU Texture is not a valid resource request. Must be created via texture_convert\n", .{});
                unreachable;
            },
        }
    }

    fn load_resource_texture(this: *This, request: ResourceRequest, textureRes: ResourceType.Texture) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        const texture = try SoftwareTexture.load(request.asset_source, textureRes.vflip);
        errdefer texture.release();

        this.id_counter += 1;
        const index = this.id_counter;

        try this.texture_sources.put(index, texture);
        errdefer _ = this.texture_sources.remove(index);

        const node = ResourceLookupNode{
            .index = index,
            .resource_name = request.asset_name,
            .resource_type = request.type,
        };
        try this.lookup.put(request.asset_name, node);
    }

    fn load_resource_shader(this: *This, request: ResourceRequest, shaderRes: ResourceType.ShaderRes) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        var shader = try Shader.load(this.allocator, request.asset_source, shaderRes.stage, shaderRes.resources);
        errdefer shader.release();

        this.id_counter += 1;
        const index = this.id_counter;

        try this.shaders.put(index, shader);
        errdefer _ = this.shaders.remove(index);

        const node = ResourceLookupNode{
            .index = index,
            .resource_name = request.asset_name,
            .resource_type = request.type,
        };
        try this.lookup.put(request.asset_name, node);
    }

    fn load_resource_raw(this: *This, request: ResourceRequest) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        const data = try Module.read_file(this.allocator, request.asset_source);
        errdefer this.allocator.free(data);

        this.id_counter += 1;
        const index = this.id_counter;

        try this.binaries.put(index, .{
            .buffer = data,
        });
        errdefer _ = this.binaries.remove(index);

        const node = ResourceLookupNode{
            .index = index,
            .resource_name = request.asset_name,
            .resource_type = request.type,
        };
        try this.lookup.put(request.asset_name, node);
    }

    pub fn free_resource(this: *This, name: []const u8) void {
        const lookup_node = this.lookup.getPtr(name);

        if (lookup_node) |node| {
            switch (node.resource_type) {
                .raw => {
                    const buffer = this.binaries.get(node.index) orelse unreachable;
                    this.allocator.free(buffer.buffer);
                    _ = this.binaries.remove(node.index);
                },
                .texture => {
                    const texture = this.texture_sources.get(node.index) orelse unreachable;
                    texture.release();
                    _ = this.texture_sources.remove(node.index);
                },
                .shader => {
                    var shader = this.shaders.getPtr(node.index) orelse unreachable;
                    shader.release();
                    _ = this.shaders.remove(node.index);
                },
                .gpu_texture => {
                    var texture = this.textures.get(node.index) orelse unreachable;
                    texture.release();
                    _ = this.textures.remove(node.index);
                },
            }

            _ = this.lookup.remove(name);
        } else {
            std.debug.print("Double free of resource `{s}`!\n", .{name});
            unreachable;
        }
    }

    pub fn deinit(this: *This) void {
        var lookup_it = this.lookup.iterator();

        while (lookup_it.next()) |kv| {
            this.free_resource(kv.key_ptr.*);
        }
    }
};

// pub const SoftwareTexture = struct {
//     const This = @This();

//     surface: [*c]sdl.SDL_Surface,

//     pub fn load(asset: []const u8) !This {
//         const allocator = host.MemAlloc;

//         const path = try get_asset_pathz(allocator, asset);
//         defer allocator.free(path);

//         const surface = sdl.IMG_Load(path.ptr);
//         defer sdl.SDL_DestroySurface(surface);

//         if (surface == null) {
//             return error.ImageLoadError;
//         }

//         const actual_surface = sdl.SDL_ConvertSurface(surface, host.INTERNAL_PIXEL_FORMAT);
//         if (actual_surface == null) {
//             return error.UnableToConvertSurface;
//         }

//         const fmt = actual_surface.*.format;
//         const details = sdl.SDL_GetPixelFormatDetails(fmt);
//         std.debug.print("Surface format: {s}\n", .{sdl.SDL_GetPixelFormatName(fmt)});
//         std.debug.print("Rmask: {x} Gmask: {x} Bmask: {x} Amask: {x}\n", .{ details.*.Rmask, details.*.Gmask, details.*.Bmask, details.*.Amask });

//         return This{ .surface = actual_surface };
//     }

//     pub fn release(this: This) void {
//         sdl.SDL_DestroySurface(this.surface);
//     }
// };
