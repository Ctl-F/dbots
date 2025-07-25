const std = @import("std");
const host = @import("host.zig");
const math = @import("math.zig");

pub const ComponentID = usize;

const DEFAULT_MAX_LIMIT: usize = 1000;

pub const Renderable = struct {
    mesh_key: []const u8,
    texture_key: []const u8,
    pipeline: ?host.PipelineID,

    projection_id: ComponentID,
    view_id: ComponentID,
    model_id: ComponentID,
};

pub const Matrix4 = math.mat4;

pub const Transform = struct {
    position: math.vec3,
    scale: math.vec3,
    rotation: math.quat,

    pub fn to_mat4(this: @This()) Matrix4 {
        _ = this;
        unreachable; //todo
    }
};

pub const ComponentTypes = enum {
    Renderable,
    Matrix4,
    Transform,
};

var glob_renderable_list = std.ArrayList(Renderable).initCapacity(host.MemAlloc, DEFAULT_MAX_LIMIT) catch unreachable; //TODO: Use sparsemap instead of array list directly
var glob_matrix_list = std.ArrayList(Matrix4).initCapacity(host.MemAlloc, DEFAULT_MAX_LIMIT) catch unreachable;
var glob_transform_list = std.ArrayList(Transform).initCapacity(host.MemAlloc, DEFAULT_MAX_LIMIT) catch unreachable;

pub const Entity = struct {};
