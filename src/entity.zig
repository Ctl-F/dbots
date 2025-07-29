const std = @import("std");
const host = @import("host.zig");
const math = @import("math.zig");

const containers = @import("containers.zig");

pub const ComponentID = usize;

const DEFAULT_NUM: usize = 1000;

pub const Renderable = struct {
    pub const UniformFunc = *const fn (this: *Renderable, renderPass: *host.RenderPass) void;

    mesh_key: []const u8,
    texture_key: []const u8,
    uniform_func: UniformFunc,
};

pub const Collider = union(enum) {};

pub const Transform = struct {
    position: math.vec3,
    rotation: math.vec3,
    scale: math.vec3,
};

pub const Entity = struct {
    transform: Transform,
    renderable: ?ComponentID,
    collider: ?ComponentID,
};

pub const Registry = struct {
    renderables: containers.SparseSet(Renderable),
    colliders: containers.SparseSet(Collider),
    entities: containers.SparseSet(Entity),
};

//var glob_renderable_list = containers.SparseSet(Renderable).initCapacity(host.MemAlloc, DEFAULT_NUM) catch unreachable;
//var glob_colliders_list = containers.SparseSet(Collider).initCapacity(host.MemAlloc, DEFAULT_NUM) catch unreachable;
//var glob_entities_list = containers.SparseSet(Entity).initCapacity(host.MemAlloc, DEFAULT_NUM) catch unreachable;
