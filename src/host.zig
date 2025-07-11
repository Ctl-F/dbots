pub const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    //@cInclude("SDL3_image/SDL_image.h");
});
const std = @import("std");
const builtin = @import("builtin");
const assets = @import("assets.zig");

pub const Input = @import("input.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const MemAlloc = switch (builtin.mode) {
    .Debug, .ReleaseSafe => dbg: {
        break :dbg gpa.allocator();
    },
    else => std.heap.c_allocator,
};

var windowptr: ?*sdl.SDL_Window = null;
var gpu_device: ?*sdl.SDL_GPUDevice = null;
var _input: ?Input = null;

pub fn device() *sdl.SDL_GPUDevice {
    if (gpu_device) |dev| {
        return dev;
    } else {
        unreachable;
    }
}

pub fn window() *sdl.SDL_Window {
    if (windowptr) |wptr| {
        return wptr;
    } else {
        unreachable;
    }
}

pub fn input_mode(mode: Input.Mode) void {
    _input = Input.init(mode);
}

pub fn input() *Input {
    if (_input) |*inp| {
        return inp;
    }
    std.debug.print("Input mode not set\n", .{});
    unreachable;
}

pub const InitOptions = struct {
    display: struct {
        width: u32,
        height: u32,
        monitor: ?u32,
    },
    title: [*c]const u8,
};

pub fn init(options: InitOptions) !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        return sdl_debug_error("init");
    }
    errdefer sdl.SDL_Quit();

    windowptr = sdl.SDL_CreateWindow(options.title, @intCast(options.display.width), @intCast(options.display.height), sdl.SDL_WINDOW_VULKAN);
    if (windowptr == null) {
        return sdl_debug_error("wincreate");
    }
    errdefer sdl.SDL_DestroyWindow(windowptr);

    if (options.display.monitor) |monitor| {
        configure_monitor(monitor) catch {
            sdl_debug(.Warn, "Windowed mode will be used.");
        };
    } else {
        _ = sdl.SDL_SetWindowPosition(windowptr, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);
    }

    gpu_device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, builtin.mode == .Debug or builtin.mode == .ReleaseSafe, null);

    if (gpu_device == null) {
        return sdl_debug_error("device create");
    }
    errdefer sdl.SDL_DestroyGPUDevice(gpu_device);

    const device_driver = sdl.SDL_GetGPUDeviceDriver(gpu_device);
    _ = sdl.SDL_SetError(device_driver);
    sdl_debug(.Info, "Device Driver");

    if (!sdl.SDL_ClaimWindowForGPUDevice(gpu_device, windowptr)) {
        return sdl_debug_error("Claim Window for GPU");
    }
}

pub fn deinit() void {
    sdl.SDL_ReleaseWindowFromGPUDevice(gpu_device, windowptr);
    sdl.SDL_DestroyGPUDevice(gpu_device);
    sdl.SDL_DestroyWindow(windowptr);
    sdl.SDL_Quit();
}

fn configure_monitor(requested: u32) !void {
    _ = requested;
    if (!sdl.SDL_SetWindowFullscreen(windowptr, true)) {
        _ = sdl.SDL_SetError("Error setting fullscreen mode");
        return error.Fullscreen;
    }
}

const SDL_DEBUG_TYPE = enum {
    Info,
    Warn,
    Error,
};

pub fn sdl_debug(sdltype: SDL_DEBUG_TYPE, msg: []const u8) void {
    const typestr = switch (sdltype) {
        .Info => "SDL_Info",
        .Warn => "SDL_Warn",
        .Error => "SDL_Error",
    };

    std.debug.print("{s}({s}): `{s}`\n", .{ typestr, msg, sdl.SDL_GetError() });
}

pub fn sdl_debug_error(msg: []const u8) anyerror {
    sdl_debug(.Error, msg);
    return error.SDL_ERROR;
}

pub const VertexElement = enum(u32) {
    Float1 = 0,
    Float2,
    Float3,
    Float4,
    Int1,
    Int2,
    Int3,
    Int4,

    fn convert(this: @This()) c_uint {
        const types = [_]c_uint{
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_INT,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_INT2,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_INT3,
            sdl.SDL_GPU_VERTEXELEMENTFORMAT_INT4,
        };
        comptime {
            const typeInfo = @typeInfo(@This());

            if (types.len != typeInfo.@"enum".fields.len) {
                @compileError("Mismatch number of enum options for static data table.");
            }
        }
        return types[@intFromEnum(this)];
    }

    pub fn element_size_bytes(this: @This()) u32 {
        const sizes = [_]u32{
            // float1-float4
            @sizeOf(f32), @sizeOf(f32), @sizeOf(f32), @sizeOf(f32),
            // int1-int4
            @sizeOf(i32), @sizeOf(i32), @sizeOf(i32), @sizeOf(i32),
        };

        comptime {
            const typeInfo = @typeInfo(@This());

            if (sizes.len != typeInfo.@"enum".fields.len) {
                @compileError("Mismatch number of enum options for static data table.");
            }
        }

        return sizes[@intFromEnum(this)];
    }

    pub fn element_count(this: @This()) u32 {
        const counts = [_]u32{
            // float1-float4
            1, 2, 3, 4,
            // int1-int4
            1, 2, 3, 4,
        };

        comptime {
            const typeInfo = @typeInfo(@This());

            if (counts.len != typeInfo.@"enum".fields.len) {
                @compileError("Mismatch number of enum options for static data table.");
            }
        }

        return counts[@intFromEnum(this)];
    }

    pub fn element_name(this: @This()) [:0]const u8 {
        const field_names = [_][:0]const u8{
            "Float1", "Float2", "Float3", "Float4",
            "Int1",   "Int2",   "Int3",   "Int4",
        };
        return field_names[@intFromEnum(this)];
    }

    pub fn size_bytes(this: @This()) u32 {
        return this.element_count() * this.element_size_bytes();
    }
};

pub const VertexFormatSpecifier = struct {
    type: VertexElement,
    offset: u32,
};

pub const MAX_VERTEX_FORMAT_SPECIFIERS = 8;

pub const VertexFormat = struct {
    const This = @This();

    formats_buffer: [MAX_VERTEX_FORMAT_SPECIFIERS]VertexFormatSpecifier,
    formats: []VertexFormatSpecifier,
    stride: u32,

    pub fn begin() This {
        var instance = This{
            .formats_buffer = undefined,
            .formats = &.{},
            .stride = 0,
        };
        instance.formats = instance.formats_buffer[0..0];
        return instance;
    }

    pub fn add(this: *This, element: VertexElement) !void {
        if (this.formats.len == this.formats_buffer.len) {
            return error.TOO_MANY_ELEMENTS;
        }

        const offset = if (this.formats.len > 0) CALC: {
            break :CALC this.formats[this.formats.len - 1].offset + this.formats[this.formats.len - 1].type.size_bytes();
        } else 0;

        this.stride += element.size_bytes();

        this.formats_buffer[this.formats.len] = .{
            .type = element,
            .offset = offset,
        };
        this.formats = this.formats_buffer[0 .. this.formats.len + 1];
    }

    pub fn display_format(this: This) void {
        if (this.formats.len == 0) {
            std.debug.print("[ Empty Vertex Format ]\n", .{});
            return;
        }

        for (this.formats) |fmt| {
            std.debug.print("[ {s}@{d:02} ]", .{ fmt.type.element_name(), fmt.offset });
        }
        std.debug.print(":Stride[{}]\n", .{this.stride});
    }
};

pub const Topology = enum {
    TriangleList,
    TriangleStrip,
    LineList,
    LineStrip,

    fn convert(this: @This()) c_uint {
        const convert_table = [_]c_uint{
            sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
            sdl.SDL_GPU_PRIMITIVETYPE_LINELIST,
            sdl.SDL_GPU_PRIMITIVETYPE_LINESTRIP,
        };

        return convert_table[@intFromEnum(this)];
    }
};

pub const PipelineConfig = struct {
    vertex_shader: assets.Shader,
    fragment_shader: assets.Shader,
    topology: Topology,
    vertex_format: VertexFormat,
    enable_depth_buffer: bool,
    enable_culling: bool,
};
// vulkan minimum number of textures per shader. Increase at your own risk
pub const MAX_RENDERPASS_TEXTURE_COUNT = 16;

pub const Pipeline = struct {
    const This = @This();

    pub const RenderPass = struct {
        command_buffer: ?*sdl.SDL_GPUCommandBuffer,
        render_pass: ?*sdl.SDL_GPURenderPass,
        swapchain_texture: ?*sdl.SDL_GPUTexture,
        frame_textures: []TextureSamplerInfo = &.{},
        texture_buffer: [MAX_RENDERPASS_TEXTURE_COUNT]TextureSamplerInfo = undefined,

        const TextureSamplerInfo = struct {
            texture: GPUTexture,
            slot: ?u32,
        };
    };

    handle: *sdl.SDL_GPUGraphicsPipeline,
    depth_texture: ?*sdl.SDL_GPUTexture,

    const DEPTH_TEXTURE_FMT = sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM;

    pub fn init(config: PipelineConfig) !This {
        var pipeline_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = config.vertex_shader.handle,
            .fragment_shader = config.fragment_shader.handle,
            .primitive_type = config.topology.convert(),
            .vertex_input_state = sdl.SDL_GPUVertexInputState{
                .vertex_buffer_descriptions = &sdl.SDL_GPUVertexBufferDescription{
                    .slot = 0,
                    .pitch = config.vertex_format.stride,
                    .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                    .instance_step_rate = 0,
                },

                .num_vertex_buffers = 1,
                .vertex_attributes = null,
                .num_vertex_attributes = 0,
            },
            .target_info = .{
                .color_target_descriptions = &sdl.SDL_GPUColorTargetDescription{
                    .format = sdl.SDL_GetGPUSwapchainTextureFormat(gpu_device, windowptr),
                },
                .num_color_targets = 1,
                .has_depth_stencil_target = config.enable_depth_buffer,
            },
        };

        if (config.enable_culling) {
            pipeline_info.rasterizer_state = sdl.SDL_GPURasterizerState{
                .cull_mode = sdl.SDL_GPU_CULLMODE_BACK,
                .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
                .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            };
        }

        const depth_tex: ?*sdl.SDL_GPUTexture = if (config.enable_depth_buffer) TEXTURE: {
            pipeline_info.target_info.depth_stencil_format = DEPTH_TEXTURE_FMT;
            pipeline_info.depth_stencil_state = sdl.SDL_GPUDepthStencilState{
                .enable_depth_test = true,
                .enable_depth_write = true,
                .enable_stencil_test = false,
                .compare_op = sdl.SDL_GPU_COMPAREOP_LESS,
                .write_mask = 0xFF,
            };

            var width: c_int = undefined;
            var height: c_int = undefined;
            _ = sdl.SDL_GetWindowSizeInPixels(windowptr, &width, &height);

            const depth_texture = sdl.SDL_CreateGPUTexture(gpu_device, &.{
                .width = @intCast(width),
                .height = @intCast(height),
                .layer_count_or_depth = 1,
                .format = DEPTH_TEXTURE_FMT,
                .usage = sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
                .num_levels = 1,
            });

            if (depth_texture == null) {
                return error.UnableToAllocateDepthBuffer;
            }
            errdefer sdl.SDL_ReleaseGPUTexture(gpu_device, depth_texture);

            break :TEXTURE depth_texture;
        } else null;

        const buffer = sdl.SDL_malloc(@sizeOf(sdl.SDL_GPUVertexAttribute) * config.vertex_format.formats.len);
        if (buffer == null) {
            return error.OutOfMemory;
        }

        defer sdl.SDL_free(buffer);

        const view: [*]sdl.SDL_GPUVertexAttribute = @ptrCast(@alignCast(buffer));

        for (config.vertex_format.formats, 0..) |element, idx| {
            view[idx] = .{
                .location = @intCast(idx),
                .buffer_slot = 0,
                .format = element.type.convert(),
                .offset = element.offset,
            };
        }

        pipeline_info.vertex_input_state.vertex_attributes = view;
        pipeline_info.vertex_input_state.num_vertex_attributes = @intCast(config.vertex_format.formats.len);

        //std.debug.print("Pipeline create\n", .{});
        const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &pipeline_info);
        if (pipeline) |handle| {
            return This{
                .handle = handle,
                .depth_texture = depth_tex,
            };
        }
        return error.FailedToCreatePipeline;
    }

    pub fn begin(this: This, clearColor: @Vector(4, f32)) !RenderPass {
        var renderPass = RenderPass{
            .command_buffer = null,
            .render_pass = null,
            .swapchain_texture = null,
            .frame_textures = &.{},
            .texture_buffer = undefined,
        };

        renderPass.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
        if (renderPass.command_buffer == null) {
            return error.UnableToObtainCommandBuffer;
        }
        //std.debug.print("Acquired Command buffer\n", .{});

        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(renderPass.command_buffer, windowptr, &renderPass.swapchain_texture, null, null)) {
            return error.UnableToObtainSwapchainTexture;
        }
        //std.debug.print("Obtained swapchain texture.\n", .{});

        var colorTargetInfo = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
        colorTargetInfo.texture = renderPass.swapchain_texture;
        colorTargetInfo.clear_color = sdl.SDL_FColor{ .r = clearColor[0], .g = clearColor[1], .b = clearColor[2], .a = clearColor[3] };
        colorTargetInfo.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
        colorTargetInfo.store_op = sdl.SDL_GPU_STOREOP_STORE;

        const depthTargetInfo: ?sdl.SDL_GPUDepthStencilTargetInfo = if (this.depth_texture != null) RES: {
            var dti = std.mem.zeroes(sdl.SDL_GPUDepthStencilTargetInfo);
            dti.texture = this.depth_texture;
            dti.clear_depth = 1.0;
            dti.clear_stencil = 0;
            dti.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
            dti.store_op = sdl.SDL_GPU_STOREOP_STORE;
            dti.stencil_load_op = sdl.SDL_GPU_LOADOP_DONT_CARE;
            dti.stencil_store_op = sdl.SDL_GPU_STOREOP_DONT_CARE;
            break :RES dti;
        } else null;

        const depthTargetInfoPtr: [*c]const sdl.SDL_GPUDepthStencilTargetInfo = if (depthTargetInfo == null) null else &depthTargetInfo.?;
        renderPass.render_pass = sdl.SDL_BeginGPURenderPass(renderPass.command_buffer, &colorTargetInfo, 1, depthTargetInfoPtr);
        //std.debug.print("Render Pass Begin\n", .{});
        sdl.SDL_BindGPUGraphicsPipeline(renderPass.render_pass, this.handle);
        //std.debug.print("Bind pipeline\n", .{});

        return renderPass;
    }

    /// uniforms and textures need to be bound before calling this
    pub fn bind_vertex_buffer(this: This, renderPass: *RenderPass, buffer: GPUBuffer) void {
        ////std.debug.print("This: {}\nRenderPass: {}\nBuffer: {}\n", .{ this, renderPass, buffer });
        _ = this;
        if (renderPass.frame_textures.len != 0) {
            if (builtin.mode == .Debug) {
                for (renderPass.frame_textures) |tex| {
                    if (tex.slot != null) {
                        std.debug.print("Warning: Non-Null texture slot was specified but will not be respected.\n", .{});
                    }
                }
            }

            var textures: [MAX_RENDERPASS_TEXTURE_COUNT]sdl.SDL_GPUTextureSamplerBinding = undefined;
            for (renderPass.frame_textures, 0..) |tex, idx| {
                textures[idx] = .{
                    .texture = tex.texture.handle,
                    .sampler = tex.texture.sampler,
                };
                //std.debug.print("Binding texture: {}|{}\n", .{ tex.texture.handle, tex.texture.sampler });
            }

            sdl.SDL_BindGPUFragmentSamplers(renderPass.render_pass, 0, &textures[0], @intCast(renderPass.frame_textures.len));
            renderPass.frame_textures = &.{};
        }

        //std.debug.print("Binding vertex buffer: {}\n", .{buffer.handle});

        const buffers = [_]sdl.SDL_GPUBufferBinding{
            sdl.SDL_GPUBufferBinding{
                .buffer = buffer.handle,
                .offset = 0,
            },
        };

        sdl.SDL_BindGPUVertexBuffers(renderPass.render_pass, 0, &buffers[0], 1);

        //std.debug.print("Draw primitives\n", .{});
        sdl.SDL_DrawGPUPrimitives(renderPass.render_pass, buffer.count, 1, 0, 0);
    }

    pub fn bind_uniform_buffer(this: This, renderPass: RenderPass, buffer: *const anyopaque, size: usize, stage: assets.Shader.Stage, slot: u32) void {
        _ = this;
        switch (stage) {
            .Vertex => {
                //std.debug.print("Bind vertex uniform data\n", .{});
                sdl.SDL_PushGPUVertexUniformData(renderPass.command_buffer, @intCast(slot), buffer, @intCast(size));
            },
            .Fragment => {
                //std.debug.print("Bind fragment uniform data\n", .{});
                sdl.SDL_PushGPUFragmentUniformData(renderPass.command_buffer, @intCast(slot), buffer, @intCast(size));
            },
        }
    }

    /// needs to  be bound BEFORE the vertex_buffer is  bound. It is when binding the vertex buffer
    /// that the bind_texture commands will actually be recorded. This will just group them together for
    /// bulk binding
    pub fn bind_texture(this: This, renderPass: *RenderPass, texture: GPUTexture) !void {
        return this.bind_texture_slot(renderPass, texture, null);
    }

    pub fn bind_texture_slot(this: This, renderPass: *RenderPass, texture: GPUTexture, slot: ?u32) !void {
        _ = this;

        if (renderPass.frame_textures.len >= MAX_RENDERPASS_TEXTURE_COUNT) {
            return error.RENDERPASS_TEXTURE_LIMIT_EXCEEDED;
        }

        const index = renderPass.frame_textures.len;
        renderPass.texture_buffer[index] = .{
            .slot = slot,
            .texture = texture,
        };
        renderPass.frame_textures = renderPass.texture_buffer[0 .. index + 1];
    }

    pub fn end(this: This, renderPass: RenderPass) !void {
        _ = this;
        //std.debug.print("Render Pass End", .{});
        sdl.SDL_EndGPURenderPass(renderPass.render_pass);
        //std.debug.print("Command Buffer Submit", .{});
        if (!sdl.SDL_SubmitGPUCommandBuffer(renderPass.command_buffer)) {
            return error.CouldNotSubmitCommandBuffer;
        }
    }

    pub fn free(this: This) void {
        //std.debug.print("Pipeline free", .{});
        sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, this.handle);
    }
};

const BufferStagingInfoDestinationTarget = union(enum) {
    buffer: Buffer,
    texture: Texture,
    none: None,

    const Buffer = struct {
        handle: ?*sdl.SDL_GPUBuffer,
    };
    const Texture = struct {
        handle: ?*sdl.SDL_GPUTexture,
        sampler: ?*sdl.SDL_GPUSampler,
        info: GPUSamplerInfo,
    };
    const None = struct {};
};

pub const BufferStagingInfo = struct {
    destination: BufferStagingInfoDestinationTarget,
    staging: ?*sdl.SDL_GPUTransferBuffer,
    total_size_bytes: usize, // we need the size so that we know how much data to transfer
    count: u32, // we need the count separate from the size so we know how many vertices there are
    keep_staging_buffer: bool,

    pub fn release(this: @This()) void {
        switch (this.destination) {
            .buffer => |b| {
                if (b.handle != null) {
                    //std.debug.print("Buffer Released via transfer buffer\n", .{});
                    sdl.SDL_ReleaseGPUBuffer(gpu_device, b.handle);
                }
            },
            .texture => |t| {
                if (t.handle != null) {
                    //std.debug.print("Texture released\n", .{});
                    sdl.SDL_ReleaseGPUTexture(gpu_device, t.handle);
                }
                if (t.sampler != null) {
                    //std.debug.print("Sampler released\n", .{});
                    sdl.SDL_ReleaseGPUSampler(gpu_device, t.sampler);
                }
            },
            .none => {
                std.debug.print("Skipping release of resources\n", .{});
            },
        }

        if (this.staging != null) {
            //std.debug.print("Transfer buffer released\n", .{});
            sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, this.staging);
        }
    }
};

pub const GPUBuffer = struct {
    handle: *sdl.SDL_GPUBuffer,
    staging_handle: ?*sdl.SDL_GPUTransferBuffer,
    count: u32,
    size: usize,

    pub fn release(this: @This()) void {
        //std.debug.print("Buffer released.\n", .{});
        sdl.SDL_ReleaseGPUBuffer(gpu_device, this.handle);

        if (this.staging_handle) |handle| {
            sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, handle);
        }
    }
};

pub const GPUTexture = struct {
    const This = @This();

    handle: *sdl.SDL_GPUTexture,
    staging_handle: ?*sdl.SDL_GPUTransferBuffer,
    sampler: *sdl.SDL_GPUSampler,
    info: GPUSamplerInfo,

    pub fn release(this: @This()) void {
        sdl.SDL_ReleaseGPUTexture(gpu_device, this.handle);
        sdl.SDL_ReleaseGPUSampler(gpu_device, this.sampler);

        if (this.staging_handle) |handle| {
            sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, handle);
        }
    }
};

pub const BufferUsageHint = enum {
    Vertex,
    Index,
    Storage,
    Sampler,

    fn convert(this: @This()) c_uint {
        const values = [_]c_uint{
            sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            sdl.SDL_GPU_BUFFERUSAGE_INDEX,
            sdl.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        };

        return values[@intFromEnum(this)];
    }
};

pub const BufferCreateInfo = struct {
    usage: BufferUsageHint,
    element_size: u32,
    num_elements: u32,
    dynamic_upload: bool,
    texture_info: ?GPUSamplerInfo,
};

pub fn begin_stage_buffer(bufferInfo: anytype) !BufferStagingInfo {
    const ptype = @TypeOf(bufferInfo);
    if (ptype == BufferCreateInfo) {
        return begin_stage_buffer_create(bufferInfo);
    }
    if (ptype == GPUBuffer) {
        return begin_stage_buffer_reupload(bufferInfo);
    }
    if (ptype == GPUTexture) {
        return begin_stage_buffer_reupload_sampler(bufferInfo);
    }
    @compileError("Invalid parameter type for `begin_stage_buffer.` Expected: BufferCreateInfo or GPUBuffer, got: " ++ @typeName(ptype));
}

fn begin_stage_buffer_reupload(buffer: GPUBuffer) !BufferStagingInfo {
    if (buffer.staging_handle == null) {
        return error.BufferIsNotMarkedForDynamicUpload;
    }

    return BufferStagingInfo{
        .destination = BufferStagingInfoDestinationTarget{ .buffer = .{buffer.handle} },
        .staging = buffer.staging_handle,
        .total_size_bytes = buffer.size,
        .count = buffer.count,
        .keep_staging_buffer = true,
    };
}

fn begin_stage_buffer_reupload_sampler(texture: GPUTexture) !BufferStagingInfo {
    if (texture.staging_handle == null) {
        return error.BufferIsNotMarkedForDynamicUpload;
    }
    return BufferStagingInfo{
        .destination = BufferStagingInfoDestinationTarget{
            .texture = .{
                .handle = texture.handle,
                .sampler = texture.sampler,
                .info = texture.info,
            },
        },
        .staging = texture.staging_handle,
        .total_size_bytes = texture.info.width * texture.info.height * BYTES_PER_PIXEL,
        .count = 1,
        .keep_staging_buffer = true,
    };
}

fn begin_stage_buffer_create(createInfo: BufferCreateInfo) !BufferStagingInfo {
    if (createInfo.usage == .Sampler) {
        return begin_stage_buffer_create_sampler(createInfo);
    }
    return begin_stage_buffer_create_buffer(createInfo);
}

fn begin_stage_buffer_create_sampler(createInfo: BufferCreateInfo) !BufferStagingInfo {
    std.debug.assert(createInfo.texture_info != null);

    const sampler_info = createInfo.texture_info.?;

    const dest_texture = sdl.SDL_CreateGPUTexture(
        gpu_device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = INTERNAL_GPU_PIXEL_FORMAT,
            .width = sampler_info.width,
            .height = sampler_info.height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = createInfo.usage.convert(),
        },
    );
    if (dest_texture == null) {
        return error.CouldNotCreateGPUTexture;
    }
    errdefer sdl.SDL_ReleaseGPUTexture(gpu_device, dest_texture);

    if (sampler_info.texture_name) |name| {
        sdl.SDL_SetGPUTextureName(gpu_device, dest_texture, name);
    }

    const dest_sampler = sdl.SDL_CreateGPUSampler(
        gpu_device,
        &.{
            .min_filter = sampler_info.min_filter.convert(),
            .mag_filter = sampler_info.mag_filter.convert(),
            .address_mode_u = sampler_info.address_policy.convert(),
            .address_mode_v = sampler_info.address_policy.convert(),
            .address_mode_w = sampler_info.address_policy.convert(),
            .mipmap_mode = sampler_info.mipmap_filter.convert_mm(),
        },
    );

    if (dest_sampler == null) {
        return error.CouldNotCreateGPUSampler;
    }
    errdefer sdl.SDL_ReleaseGPUSampler(gpu_device, dest_sampler);

    const staging_buffer = sdl.SDL_CreateGPUTransferBuffer(
        gpu_device,
        &.{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = sampler_info.width * sampler_info.height * BYTES_PER_PIXEL,
        },
    );
    if (staging_buffer == null) {
        return error.CouldNotAllocateStagingBuffer;
    }

    return .{
        .destination = BufferStagingInfoDestinationTarget{
            .texture = .{
                .handle = dest_texture,
                .sampler = dest_sampler,
                .info = sampler_info,
            },
        },
        .staging = staging_buffer,
        .total_size_bytes = sampler_info.width * sampler_info.height * BYTES_PER_PIXEL,
        .count = 1,
        .keep_staging_buffer = createInfo.dynamic_upload,
    };
}

fn begin_stage_buffer_create_buffer(createInfo: BufferCreateInfo) !BufferStagingInfo {
    const total_buffer_size = createInfo.element_size * createInfo.num_elements;

    const dest_buffer = sdl.SDL_CreateGPUBuffer(
        gpu_device,
        &.{
            .usage = createInfo.usage.convert(),
            .size = @intCast(total_buffer_size),
        },
    );
    if (dest_buffer == null) {
        return error.CouldNotAllocateVertexBuffer;
    }
    errdefer sdl.SDL_ReleaseGPUBuffer(gpu_device, dest_buffer);

    const staging_buffer = sdl.SDL_CreateGPUTransferBuffer(gpu_device, &.{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(total_buffer_size),
    });
    if (staging_buffer == null) {
        return error.CouldNotAllocateStagingBuffer;
    }
    errdefer sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, staging_buffer);

    return BufferStagingInfo{
        .destination = BufferStagingInfoDestinationTarget{
            .buffer = .{
                .handle = dest_buffer,
            },
        },
        .staging = staging_buffer,
        .total_size_bytes = total_buffer_size,
        .count = @intCast(createInfo.num_elements),
        .keep_staging_buffer = createInfo.dynamic_upload,
    };
}

pub fn map_stage_buffer(comptime T: type, stagingInfo: BufferStagingInfo) ![*]T {
    const transfer_buffer = sdl.SDL_MapGPUTransferBuffer(gpu_device, stagingInfo.staging, false);
    if (transfer_buffer == null) {
        return error.CouldNotMapStagingBuffer;
    }

    return @ptrCast(@alignCast(transfer_buffer));
}

pub fn submit_stage_buffer(comptime result: type, stagingInfo: *BufferStagingInfo) !result {
    if (result == GPUBuffer) {
        return submit_stage_buffer_buffer(stagingInfo);
    }
    if (result == GPUTexture) {
        return submit_stage_buffer_sampler(stagingInfo);
    }
    @compileError("Invalid result type for submit stage buffer. Expected GPUBuffer or GPUTexture");
}

pub fn submit_stage_buffer_sampler(stagingInfo: *BufferStagingInfo) !GPUTexture {
    const destination = switch (stagingInfo.destination) {
        .texture => |t| t,
        else => return error.InvalidConfigurationForTextureSubmission,
    };

    sdl.SDL_UnmapGPUTransferBuffer(gpu_device, stagingInfo.staging);

    const commandBuffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
    const copyPass = sdl.SDL_BeginGPUCopyPass(commandBuffer);

    sdl.SDL_UploadToGPUTexture(
        copyPass,
        &.{
            .transfer_buffer = stagingInfo.staging,
            .offset = 0,
        },
        &.{
            .texture = destination.handle,
            .w = destination.info.width,
            .h = destination.info.height,
            .d = 1,
        },
        false,
    );

    sdl.SDL_EndGPUCopyPass(copyPass);
    if (!sdl.SDL_SubmitGPUCommandBuffer(commandBuffer)) {
        return error.CouldNotCopyBuferData;
    }

    if (!stagingInfo.keep_staging_buffer) {
        sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, stagingInfo.staging);
        stagingInfo.staging = null;
    }

    // defer {
    //     stagingInfo.destination = .none;
    //     stagingInfo.release();
    // }

    if (destination.info.enable_mipmaps) {
        const buffer2 = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
        sdl.SDL_GenerateMipmapsForGPUTexture(buffer2, destination.handle);
        if (!sdl.SDL_SubmitGPUCommandBuffer(buffer2)) {
            return error.CouldNotGenerateMipmaps;
        }
    }

    return GPUTexture{
        .handle = stagingInfo.destination.texture.handle.?,
        .sampler = stagingInfo.destination.texture.sampler.?,
        .info = stagingInfo.destination.texture.info,
        .staging_handle = stagingInfo.staging,
    };
}

pub fn submit_stage_buffer_buffer(stagingInfo: *BufferStagingInfo) !GPUBuffer {
    const destination = switch (stagingInfo.destination) {
        .buffer => |b| b,
        else => return error.InvalidConfigurationForBufferSubmission,
    };

    sdl.SDL_UnmapGPUTransferBuffer(gpu_device, stagingInfo.staging);

    const commandBuffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);

    if (commandBuffer == null) {
        return error.NullCommandBuffer;
    }

    const copyPass = sdl.SDL_BeginGPUCopyPass(commandBuffer);

    if (copyPass == null) {
        return error.NullCopyPass;
    }

    sdl.SDL_UploadToGPUBuffer(copyPass, &.{
        .transfer_buffer = stagingInfo.staging,
        .offset = 0,
    }, &.{
        .buffer = destination.handle,
        .offset = 0,
        .size = @intCast(stagingInfo.total_size_bytes),
    }, false);

    sdl.SDL_EndGPUCopyPass(copyPass);
    if (!sdl.SDL_SubmitGPUCommandBuffer(commandBuffer)) {
        return error.CouldNotCopyBufferData;
    }

    if (!stagingInfo.keep_staging_buffer) {
        sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, stagingInfo.staging);
        stagingInfo.staging = null;
    }

    // defer {
    //     stagingInfo.destination = .none;
    //     stagingInfo.release();
    // }

    return GPUBuffer{
        .handle = destination.handle.?,
        .staging_handle = stagingInfo.staging,
        .count = stagingInfo.count,
        .size = stagingInfo.total_size_bytes,
    };
}

pub const GPUSamplerFilter = enum {
    Linear,
    Nearest,

    // TODO: Convert to table lookup
    fn convert(this: @This()) c_uint {
        return switch (this) {
            .Linear => sdl.SDL_GPU_FILTER_LINEAR,
            .Nearest => sdl.SDL_GPU_FILTER_NEAREST,
        };
    }

    fn convert_mm(this: @This()) c_uint {
        return switch (this) {
            .Linear => sdl.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
            .Nearest => sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        };
    }
};

pub const GPUSamplerAddressPolicy = enum {
    Repeat,
    Clamp,

    // TODO: convert to table lookup
    fn convert(this: @This()) c_uint {
        return switch (this) {
            .Repeat => sdl.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .Clamp => sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        };
    }
};

pub const GPUSamplerInfo = struct {
    width: u32,
    height: u32,
    min_filter: GPUSamplerFilter,
    mag_filter: GPUSamplerFilter,
    mipmap_filter: GPUSamplerFilter,
    address_policy: GPUSamplerAddressPolicy,
    enable_mipmaps: bool,
    texture_name: ?[*c]const u8,
};

pub const INTERNAL_PIXEL_FORMAT = sdl.SDL_PIXELFORMAT_RGBA8888;
pub const INTERNAL_GPU_PIXEL_FORMAT = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
pub const BYTES_PER_PIXEL = 4;

// pub fn create(texture: assets.SoftwareTexture, samplerInfo: GPUSamplerInfo) !This {
//     const sampler = sdl.SDL_CreateGPUSampler(gpu_device, .{
//         .min_filter = samplerInfo.min_filter.convert(),
//         .mag_filter = samplerInfo.mag_filter.convert(),
//         .address_mode_u = samplerInfo.address_policy.convert(),
//         .address_mode_v = samplerInfo.address_policy.convert(),
//         .address_mode_w = samplerInfo.address_policy.convert(),
//         .mipmap_mode = samplerInfo.mipmap_filter.convert_mm(),
//     });

//     if (sampler == null) {
//         return error.CouldNotCreateSampler;
//     }
//     errdefer sdl.SDL_ReleaseGPUSampler(gpu_device, sampler);

//     const tex = sdl.SDL_CreateGPUTexture(gpu_device, .{
//         .type = sdl.SDL_GPU_TEXTURETYPE_2D,
//         .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
//         .width = texture.surface.*.w,
//         .height = texture.surface.*.h,
//         .layer_count_or_depth = 1,
//         .num_levels = 1,
//         .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
//     });

//     if (tex == null) {
//         return error.CouldNotUploadGPUTexture;
//     }
//     errdefer sdl.SDL_ReleaseGPUTexture(tex);

//     if (samplerInfo.texture_name) |name| {
//         sdl.SDL_SetGPUTextureName(gpu_device, tex, name);
//     }

//     return This{
//         .handle = tex,
//         .sampler = sampler,
//         .enable_mipmaps = samplerInfo.enable_mipmaps,
//     };
//}
