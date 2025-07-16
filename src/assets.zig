const std = @import("std");
const host = @import("host.zig");
const sdl = host.sdl;

const stb = @cImport(@cInclude("stb_image.h"));

const Module = @This();

const obj = @import("obj.zig");

pub const Vertex = obj.Vertex;

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

    return read_file_resolved(allocator, path);
}

pub fn read_file_options(
    allocator: std.mem.Allocator,
    filename: []const u8,
    comptime alignment: u29,
    comptime sentinel: ?u8,
) !(if (sentinel) |s| [:s]align(alignment) u8 else []align(alignment) u8) {
    const path = try get_asset_path(allocator, filename);
    defer allocator.free(path);

    return read_file_resolved_options(allocator, path, alignment, sentinel);
}

pub fn read_file_resolved(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();

    return try file.readToEndAlloc(allocator, stat.size);
}

pub fn read_file_resolved_options(allocator: std.mem.Allocator, filename: []const u8, comptime alignment: u29, comptime sentinel: ?u8) !(if (sentinel) |s| [:s]align(alignment) u8 else []align(alignment) u8) {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    return try file.readToEndAllocOptions(allocator, stat.size, stat.size, alignment, sentinel);
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
    mesh: Mesh,
    gpu_texture: GPUTexture,
    gpu_buffer: GPUBuffer,

    pub const Raw = struct {};
    pub const Mesh = struct {
        vertex_count: usize,
    };
    pub const ShaderRes = struct {
        stage: Shader.Stage,
        resources: Shader.ResourceConfig,
    };
    pub const Texture = struct {
        vflip: bool,
    };
    pub const GPUTexture = struct {};
    pub const GPUBuffer = struct {};
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
    buffers: std.AutoHashMap(usize, host.GPUBuffer),
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
            .buffers = std.AutoHashMap(usize, host.GPUBuffer).init(allocator),
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
            .raw, .mesh => if (T != RawBuffer) {
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
            .gpu_buffer => if (T != host.GPUBuffer) {
                std.debug.print("Incorrect resource type requested: {s} expected GPUBuffer\n", .{@typeName(T)});
                unreachable;
            },
        }
    }

    pub fn get_lookup_info(this: *This, key: []const u8) ?ResourceType {
        const lookup = this.lookup.get(key) orelse return null;
        return lookup.resource_type;
    }

    pub fn get_ptr(this: *This, comptime T: type, key: []const u8) ?*T {
        const lookup = this.lookup.get(key) orelse return null;
        assert_valid_type(T, lookup.resource_type);

        return switch (T) {
            RawBuffer => this.binaries.getPtr(lookup.index),
            Shader => this.shaders.getPtr(lookup.index),
            SoftwareTexture => this.texture_sources.getPtr(lookup.index),
            host.GPUTexture => this.textures.getPtr(lookup.index),
            host.GPUBuffer => this.buffers.getPtr(lookup.index),
            else => {
                @compileError("Unexpected type: " ++ @typeName(T));
            },
        };
    }

    fn load_resource(this: *This, request: ResourceRequest) !void {
        switch (request.type) {
            .raw => {
                return this.load_resource_raw(request);
            },
            .mesh => {
                return this.load_resource_obj(request);
            },
            .shader => |s| {
                return this.load_resource_shader(request, s);
            },
            .texture => |t| {
                return this.load_resource_texture(request, t);
            },
            .gpu_texture => {
                std.debug.print("GPU Texture is not a valid resource request. Must be created via texture conversion\n", .{});
                unreachable;
            },
            .gpu_buffer => {
                std.debug.print("Loading GPUBuffers directly is not a valid resource request. Must be created via buffer conversion\n", .{});
            },
        }
    }

    fn load_resource_texture(this: *This, request: ResourceRequest, textureRes: ResourceType.Texture) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        const texture = try SoftwareTexture.load(request.asset_source, textureRes.vflip);
        errdefer texture.release();

        try this.insert_resource(SoftwareTexture, texture, request.asset_name, request.type);
    }

    fn load_resource_shader(this: *This, request: ResourceRequest, shaderRes: ResourceType.ShaderRes) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        var shader = try Shader.load(this.allocator, request.asset_source, shaderRes.stage, shaderRes.resources);
        errdefer shader.release();

        try this.insert_resource(Shader, shader, request.asset_name, request.type);
    }

    fn load_resource_raw(this: *This, request: ResourceRequest) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        const data = try Module.read_file(this.allocator, request.asset_source);
        errdefer this.allocator.free(data);

        try this.insert_resource(RawBuffer, .{ .buffer = data }, request.asset_name, request.type);
    }

    fn load_resource_obj(this: *This, request: ResourceRequest) !void {
        if (this.lookup.contains(request.asset_name)) {
            return error.ResourceDoubleLoad;
        }

        const data = try Module.read_file_options(this.allocator, request.asset_source, @alignOf(u32), null);
        defer this.allocator.free(data);

        const vertices = try obj.load_mesh(host.MemAlloc, data);

        try this.insert_resource(RawBuffer, .{
            .buffer = @ptrCast(vertices),
        }, request.asset_name, .{
            .mesh = .{
                .vertex_count = vertices.len,
            },
        });
    }

    fn insert_resource(this: *This, comptime T: type, item: T, name: []const u8, resType: ResourceType) !void {
        this.id_counter += 1;
        const index = this.id_counter;

        const list = switch (T) {
            RawBuffer => &this.binaries,
            Shader => &this.shaders,
            SoftwareTexture => &this.texture_sources,
            host.GPUTexture => &this.textures,
            host.GPUBuffer => &this.buffers,
            else => @compileError("Asset type: " ++ @typeName(T) ++ " is not supported"),
        };

        std.debug.assert(!this.lookup.contains(name));
        std.debug.assert(!list.contains(index));

        try list.put(index, item);
        errdefer _ = list.remove(index);

        const node = ResourceLookupNode{
            .index = index,
            .resource_name = name,
            .resource_type = resType,
        };
        try this.lookup.put(name, node);
    }

    pub const TextureUploadInfo = struct {
        source_name: []const u8,
        dest_name: []const u8,
        info: host.GPUSamplerInfo,
    };

    pub const BufferUploadInfo = struct {
        source_name: []const u8,
        dest_name: []const u8,
        info: host.BufferCreateInfo,
    };

    pub fn add_texture_copy(this: *This, texture: TextureUploadInfo, copyPass: *host.CopyPass) !host.CopyPass.tag_t {
        const config = host.BufferCreateInfo{
            .dynamic_upload = false,
            .element_size = undefined,
            .num_elements = undefined,
            .texture_info = texture.info,
            .usage = .Sampler,
        };

        const swTexture = this.get(SoftwareTexture, texture.source_name) orelse return error.InvalidAssetName;

        const stage = try host.begin_stage_buffer(config);
        const buffer = try host.map_stage_buffer(u8, stage);
        const size: usize = @intCast(swTexture.width * swTexture.height * swTexture.bytes_per_pixel);
        const view = buffer[0..size];
        @memcpy(view, @as([*c]const u8, @ptrCast(@alignCast(swTexture.pixels)))[0..size]);

        const tag = try copyPass.new_tag(texture.dest_name);
        try copyPass.add_stage_buffer(stage, tag);

        return tag;
    }

    pub fn add_buffer_copy(this: *This, info: BufferUploadInfo, copyPass: *host.CopyPass) !host.CopyPass.tag_t {
        const binary = this.get(RawBuffer, info.source_name) orelse return error.InvalidAssetName;

        const stage = try host.begin_stage_buffer(info.info);
        const buffer = try host.map_stage_buffer(u8, stage);
        const view = buffer[0..binary.buffer.len];
        @memcpy(view, binary.buffer);

        const tag = try copyPass.new_tag(info.dest_name);
        try copyPass.add_stage_buffer(stage, tag);

        return tag;
    }

    pub fn claim_copy_result(this: *This, comptime T: type, copyPass: host.CopyPass, name: []const u8) !void {
        const tag = copyPass.lookup_tag(name) orelse return error.InvalidAssetName;
        const result = copyPass.get_result(T, tag) orelse unreachable;
        errdefer result.release();

        const info = switch (T) {
            host.GPUTexture => ResourceType{ .gpu_texture = .{} },
            host.GPUBuffer => ResourceType{ .gpu_buffer = .{} },
            else => @compileError("Received type `" ++ @typeName(T) ++ "` not allowed as a copy result"),
        };

        try this.insert_resource(T, result, name, info);
    }

    pub fn assert_asset_exists(this: This, comptime T: type, name: []const u8) void {
        const lookup = this.lookup.get(name) orelse unreachable;
        switch (T) {
            RawBuffer => std.debug.assert(lookup.resource_type == .raw or lookup.resource_type == .mesh),
            Shader => std.debug.assert(lookup.resource_type == .shader),
            SoftwareTexture => std.debug.assert(lookup.resource_type == .texture),
            host.GPUTexture => std.debug.assert(lookup.resource_type == .gpu_texture),
            host.GPUBuffer => std.debug.assert(lookup.resource_type == .gpu_buffer),
            else => unreachable,
        }
    }

    pub fn convert_textures(this: *This, textures: []const TextureUploadInfo) !void {
        std.debug.assert(textures.len <= host.CopyPass.BATCH_SIZE);

        var copyPass = host.CopyPass.init(host.MemAlloc);
        defer copyPass.deinit();

        var tags: [host.CopyPass.BATH_SIZE]host.tag_t = undefined;

        for (textures, 0..) |info, idx| {
            tags[idx] = try this.add_texture_to_copy_pass(info, &copyPass);
        }

        try copyPass.submit();

        for (0..textures.len) |idx| {
            // this should never be null because we have explicitly obtained every one of these tags in the first loop
            // of this same function
            // and we have (theoretically) successfully submitted the copyPass.
            const gtexture = copyPass.get_result(host.GPUTexture, tags[idx]) orelse unreachable;

            try this.insert_resource(host.GPUTexture, gtexture, textures[idx].dest_name, .{ .gpu_texture = .{} });
        }
        copyPass.claim_ownership_of_results();
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
                .mesh => |m| {
                    const buffer = this.binaries.get(node.index) orelse unreachable;
                    const correct_view: []Vertex = @as([*]Vertex, @ptrCast(@alignCast(buffer.buffer.ptr)))[0..m.vertex_count];
                    this.allocator.free(correct_view);
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
                .gpu_buffer => {
                    var buffer = this.buffers.get(node.index) orelse unreachable;
                    buffer.release();
                    _ = this.buffers.remove(node.index);
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
