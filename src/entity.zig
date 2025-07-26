const std = @import("std");
const host = @import("host.zig");
const math = @import("math.zig");

const containers = @import("containers.zig");

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

pub const ComponentFlags = packed struct {
    has_renderable: bool,
    has_matrix4: bool,
    has_transform: bool,
};

pub const Components = struct {
    renderable: ?containers.SparseKey,
    matrix4: ?containers.SparseKey,
    transform: ?containers.SparseKey,
};

pub const Entity = struct {
    component_flags: ComponentFlags,
    components: Components,
};

var glob_renderable_list = containers.SparseSet(Renderable).initCapacity(host.MemAlloc, DEFAULT_MAX_LIMIT) catch unreachable;
var glob_matrix_list = containers.SparseSet(Matrix4).initCapacity(host.MemAlloc, DEFAULT_MAX_LIMIT) catch unreachable;
var glob_transform_list = containers.SparseSet(Transform).initCapacity(host.MemAlloc, DEFAULT_MAX_LIMIT) catch unreachable;
var glob_entities_list = containers.SparseSet(Entity).init(host.MemAlloc);
