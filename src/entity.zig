const std = @import("std");
const host = @import("host.zig");
const math = @import("math.zig");
const camera = @import("camera.zig");
const assets = @import("assets.zig");

const containers = @import("containers.zig");

pub const ComponentID = usize;

const InitialCapacity = 1000;

pub const Collider = union(enum) {
    box: AABB,
    sphere: Sphere,

    pub fn get_aabb(this: *@This(), origin: math.vec3) AABB {
        switch (this) {
            .box => |b| {
                return AABB{
                    .position = origin.add(b.position),
                    .size = b.size,
                };
            },
            .sphere => |s| return .{
                .position = origin.add(s.position.sub(math.vec3.set(s.radius))),
                .size = math.vec3.set(s.radius).scale(2),
            },
        }
    }

    pub const AABB = containers.Dim3D;
    pub const Sphere = struct {
        position: math.vec3,
        radius: f32,
    };
};

pub const PhysicsBody = struct {
    position: math.vec3,
    velocity: math.vec3,
    collider: Collider,
};

// renderables that use the standard mesh pipeline and vertex format
pub const StandardRenderable = struct {
    mesh: host.GPUBuffer,
    texture: ?host.GPUTexture,
    transform: math.mat4,
};

/// a Controller is an instance that has no position and no direct component/renderable
/// it's intended to hold logic to control and manage instances, timelines, and rendering
/// but it is not a "spatial" instance like a GameObject is, it has no physical body, and thus
/// is stored and processed separately from the GameObjects
pub const Controller = struct {
    const This = @This();

    context: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        on_scene_load: *const fn (scene: *Scene, context: *anyopaque) anyerror!void,
        on_scene_unload: *const fn (scene: *Scene, context: *anyopaque) anyerror!void,
        on_scene_prestep: *const fn (scene: *Scene, context: *anyopaque, dt: f32) anyerror!void,
        on_scene_poststep: *const fn (scene: *Scene, context: *anyopaque, dt: f32) anyerror!void,
        on_scene_predraw: *const fn (scene: *Scene, context: *anyopaque) anyerror!void,
        on_scene_postdraw: *const fn (scene: *Scene, context: *anyopaque) anyerror!void,
    };

    pub inline fn scene_load(this: This, scene: *Scene) anyerror!void {
        return try this.vtable.on_scene_load(scene, this.context);
    }
    pub inline fn scene_unload(this: This, scene: *Scene) anyerror!void {
        return try this.vtable.on_scene_unload(scene, this.context);
    }
    pub inline fn scene_prestep(this: This, scene: *Scene, dt: f32) anyerror!void {
        return try this.vtable.on_scene_prestep(scene, this.context, dt);
    }
    pub inline fn scene_poststep(this: This, scene: *Scene, dt: f32) anyerror!void {
        return try this.vtable.on_scene_poststep(scene, this.context, dt);
    }
    pub inline fn scene_predraw(this: This, scene: *Scene) anyerror!void {
        return try this.vtable.on_scene_predraw(scene, this.context);
    }
    pub inline fn scene_postdraw(this: This, scene: *Scene) anyerror!void {
        return try this.vtable.on_scene_postdraw(scene, this.context);
    }
};

// keep GameObject trivially copyable
// e.g. I can copy the game object and since it's just
// pointers and references, then I don't have to worry
// about losing data on copy, shallow copies produce functionally
// equivelent instances
pub const GameObject = struct {
    const This = @This();
    body: PhysicsBodySet.Ref,
    mesh: ?RenderableSet.Ref,
    context: *anyopaque,
    vtable: VTable,

    pub fn get_aabb(this: *const GameObject) Collider.AABB {
        const body = this.body.get();

        return body.collider.get_aabb(body.position);
    }

    pub const VTable = struct {
        on_create: *const fn (base: *GameObject, scene: *Scene, context: *anyopaque) anyerror!void,
        on_destroy: *const fn (base: *GameObject, scene: *Scene, context: *anyopaque) void,
        on_step: *const fn (base: *GameObject, scene: *Scene, context: *anyopaque, dt: f32) anyerror!void,
    };

    pub inline fn create(this: *This, scene: *Scene) anyerror!void {
        return try this.vtable.on_create(this, scene, this.context);
    }
    pub inline fn destroy(this: *This, scene: *Scene) void {
        return this.vtable.on_destroy(this, scene, this.context);
    }
    pub inline fn step(this: *This, dt: f32, scene: *Scene) anyerror!void {
        return try this.vtable.on_step(this, scene, this.context, dt);
    }

    pub inline fn empty(body: PhysicsBodySet.Ref) This {
        return This{
            .body = body,
            .context = &DummyContext,
            .vtable = DummyVTable,
            .mesh = null,
        };
    }

    const DummyVTable = VTable{
        .on_create = dummy_create,
        .on_destroy = dummy_destroy,
        .on_step = dummy_step,
    };
    const DummyContextType = struct {};
    const DummyContext = DummyContextType{};

    fn dummy_create(base: *GameObject, scene: *Scene, context: *anyopaque) anyerror!void {
        _ = base;
        _ = scene;
        _ = context;
    }
    fn dummy_destroy(base: *GameObject, scene: *Scene, context: *anyopaque) void {
        _ = base;
        _ = scene;
        _ = context;
    }
    fn dummy_step(base: *GameObject, scene: *Scene, context: *anyopaque, dt: f32) anyerror!void {
        _ = base;
        _ = scene;
        _ = context;
        _ = dt;
    }
};

pub const ScenePipeline = struct {
    const This = @This();

    pipeline: host.Pipeline,
    renderables: RenderableSet,
    load_op: host.Pipeline.RenderPassLoad,

    // per renderpass
    on_pass_begin: ?*const fn (this: *This, scene: *Scene, renderPass: *host.Pipeline.RenderPass) anyerror!void,
    on_pass_end: ?*const fn (this: *This, scene: *Scene, renderPass: *host.Pipeline.RenderPass) anyerror!void,

    // per renderable
    on_draw: ?*const fn (this: *This, scene: *Scene, renderPass: *host.Pipeline.RenderPass, renderable: RenderableSet.Ref) anyerror!void,

    pub fn init(pipeline: host.Pipeline, load_op: host.Pipeline.RenderPassLoad) !This {
        return This{
            .pipeline = pipeline,
            .renderables = RenderableSet.init(host.MemAlloc),
            .on_pass_begin = null,
            .on_pass_end = null,
            .on_pre_draw = null,
            .load_op = load_op,
        };
    }

    pub fn add_renderable(this: *This, renderable: StandardRenderable) !RenderableSet.Ref {
        const key = try this.renderables.add(renderable);
        return this.renderables.to_ref(key) catch unreachable;
    }

    pub fn remove_renderable(this: *This, renderable: RenderableSet.Ref) void {
        std.debug.assert(renderable.parent == &this.renderables);
        this.renderables.remove(renderable.key);
    }

    pub fn draw(this: *This, scene: *Scene, existing: ?host.Pipeline.RenderPass) !host.Pipeline.RenderPass {
        var renderPass = try this.pipeline.begin(this.load_op, existing);

        if (this.on_pass_begin) |begin| {
            try begin(this, scene, &renderPass);
        }

        if (this.on_draw) |render| {
            for (this.renderables.items()) |ref| {
                try render(this, scene, &renderPass, ref);
            }
        }

        if (this.on_pass_end) |end| {
            try end(this, scene, &renderPass);
        }

        this.pipeline.end(&renderPass);

        return renderPass;
    }

    pub fn deinit(this: *This) void {
        this.pipeline.free();
        this.renderables.deinit();
    }
};

const PhysicsBodySet = containers.SparseSet(PhysicsBody);
const RenderableSet = containers.SparseSet(StandardRenderable);
//const RenderableRefSet = containers.SparseSet(RenderableSet.Ref);
const GameObjectSet = containers.SparseSet(GameObject);
const ControllerSet = containers.SparseSet(Controller);
const SpatialTree = containers.FixedSpatialTree(GameObject, GameObject.get_aabb, 6);

pub const Scene = struct {
    const MAX_PIPELINES = 4;

    projection: math.mat4,
    view: math.mat4,
    active_objects: SpatialTree,
    inactive_objects: SpatialTree, // TODO: Change to a SpatialTree mirroring the active_objects
    new_objects: GameObjectSet,
    dead_objects: std.ArrayList(GameObjectSet.Ref),
    physics_bodies: PhysicsBodySet,
    resources: assets.SceneResources,
    controllers: ControllerSet,
    dirty_buffer: std.ArrayList(DirtyObject),
    pipeline_buffer: [MAX_PIPELINES]?ScenePipeline,

    /// takes ownership of provided pipeline
    pub fn init(boundry: containers.Dim3D) !This {
        var active_objects = try SpatialTree.init_capacity(host.MemAlloc, boundry, InitialCapacity);
        errdefer active_objects.deinit();

        var inactive_objects = try SpatialTree.init_capacity(host.MemAlloc, InitialCapacity);
        errdefer inactive_objects.deinit();

        var dead_objects = try std.ArrayList(GameObjectSet.Ref).initCapacity(host.MemAlloc, InitialCapacity);
        errdefer dead_objects.deinit();

        var new_objects = try GameObjectSet.init_capacity(host.MemAlloc, InitialCapacity);
        errdefer new_objects.deinit();

        var object_buffer = try std.ArrayList(DirtyObject).initCapacity(host.MemAlloc, InitialCapacity);
        errdefer object_buffer.deinit();

        return This{
            .projection = math.mat4.identity(),
            .view = math.mat4.identity(),
            .active_objects = active_objects,
            .inactive_objects = inactive_objects,
            .dead_objects = dead_objects,
            .new_objects = new_objects,
            .physics_bodies = PhysicsBodySet.init(host.MemAlloc),
            .resources = assets.SceneResources.init(host.MemAlloc),
            .controllers = ControllerSet.init(host.MemAlloc),
            .object_buffer = object_buffer,
            .pipeline_list = [_]?ScenePipeline{null} ** MAX_PIPELINES,
        };
    }

    pub fn deinit(this: *This) void {
        for (this.object_buffer.items) |go| {
            go.destroy(this);
        }

        for (this.active_objects.instances.items()) |*instance| {
            instance.destroy(this);
        }
        for (this.inactive_objects.instances.items()) |*instance| {
            instance.destroy(this);
        }
        // should be empty but just in case
        for (this.dead_objects.items) |*instance| {
            instance.destroy(this);
        }

        for (this.controllers.items()) |*controller| {
            controller.scene_unload(this);
        }

        this.active_objects.deinit();
        this.dead_objects.deinit();
        this.inactive_objects.deinit();
        this.physics_bodies.deinit();
        this.resources.deinit();
        this.controllers.deinit();
        this.dirty_buffer.deinit();

        var idx: usize = 0;
        while (&this.pipeline_buffer[idx]) |*pipeline| : (idx += 1) {
            pipeline.deinit();
        }
    }

    pub fn promote_new_instances(this: *This) !void {
        for (this.new_objects.items()) |new_obj| {
            const idx = try this.active_objects.insert(new_obj);
            const ref = this.active_objects.instances.get_ptr(idx).?;
            try ref.create();
        }
        this.new_objects.clear();
    }

    // TODO: Add tagging system for fast gameobject lookup without linear iteration
    // through the spatial tree and without tree searching from object bbox

    pub fn update(this: *This, dt: f32) anyerror!void {

        // Promote any new objects
        // this relies on GameObjects themselves being trivially copyable
        // remember: You shouldn't store a GameObject reference for more than a frame.
        try this.promote_new_instances();

        // update controllers (prestep)
        for (this.controllers.items()) |controller| {
            try controller.scene_prestep(this, dt);
        }

        // update active objects
        for (this.active_objects.instances.items(), 0..) |*obj, dense_idx| {
            const start = obj.get_aabb();

            try obj.step(dt, this);

            const end = obj.get_aabb();

            if (start != end) {
                try this.dirty_buffer.append(.{
                    .old_position = start,
                    .dense_index = dense_idx,
                });
            }
        }

        for (this.physics_bodies) |*body| {
            body.position = body.position.add(body.velocity.scale(dt));
            //TODO: Default Collision Checking??
        }

        // update controllers (poststep)
        for (this.controllers.items()) |controller| {
            try controller.scene_poststep(this, dt);
        }

        // update dirty instances
        for (this.dirty_buffer.items) |dirty| {
            const sparse_key = this.active_objects.instances.sparse_from_dense(dirty.dense_index);
            try this.active_objects.update(sparse_key, dirty.old_position);
        }
        this.dirty_buffer.clearRetainingCapacity();

        // kill dead instances
        for (this.dead_objects.items) |dead| {
            dead.destroy(this);
            this.active_objects.remove(dead);
        }
        this.dead_objects.clearRetainingCapacity();
    }

    pub fn render(this: *This) !void {
        std.debug.assert(this.pipeline_buffer[0] != null);

        for (this.controllers.items()) |controller| {
            try controller.scene_predraw(this);
        }

        var index: usize = 0;
        var rolloverRenderPass: ?host.Pipeline.RenderPass = null;
        while (this.pipeline_buffer[index]) |pipeline| : (index += 1) {
            rolloverRenderPass = try pipeline.draw(this, rolloverRenderPass);
        }

        for (this.controllers.items()) |controller| {
            try controller.scene_postdraw(this);
        }
    }

    pub fn instance_create(this: *This, position: math.vec3, collider: Collider) !GameObjectSet.Ref {
        const body = try this.pbody_create(position, collider);
        const key = try this.new_objects.add(GameObject.empty(body));
        return this.new_objects.to_ref(key);
    }

    pub fn instance_destroy(this: *This, instance: GameObjectSet.Ref) !void {
        try this.dead_objects.append(instance);
    }

    pub fn deactivate_region(this: *This, area: Collider.AABB) !void {
        var results_buffer = [_]?GameObjectSet.Ref{null} ** InitialCapacity;

        while (true) {
            _ = this.active_objects.find(&results_buffer, area);

            var idx: usize = 0;
            while (results_buffer[idx]) |ref| : (idx += 1) {
                _ = try this.inactive_objects.insert(ref.get().*);
                this.active_objects.remove_by_key(ref.key);
            }

            if (idx < results_buffer.len) {
                break;
            }
            @memset(&results_buffer, null);
            continue;
        }
    }

    pub fn activate_region(this: *This, area: Collider.AABB) !void {
        var results_buffer = [_]?GameObjectSet.Ref{null} ** InitialCapacity;

        while (true) {
            _ = this.inactive_objects.find(&results_buffer, area);

            var idx: usize = 0;
            while (results_buffer[idx]) |ref| : (idx += 1) {
                _ = try this.active_objects.insert(ref.get().*);
                this.inactive_objects.remove_by_key(ref.key);
            }

            if (idx < results_buffer.len) {
                break;
            }

            @memset(&results_buffer, null);
            continue;
        }
    }

    pub fn add_pipeline(this: *This, pipeline: ScenePipeline, index: usize) void {
        std.debug.assert(index < this.pipeline_buffer.len);

        inline for (0..(index - 1)) |idx| {
            std.debug.assert(this.pipeline_buffer[idx] != null);
        }

        this.pipeline_buffer[index] = pipeline;
    }

    pub fn remove_pipeline(this: *This, index: usize) void {
        std.debug.assert(index < this.pipeline_buffer.len);

        if (this.pipeline_buffer[index] == null) return;

        this.pipeline_buffer[index].?.deinit();
        this.pipeline_buffer[index] = null;
    }

    pub fn register_renderable(this: *This, pipeline_index: usize, renderable: RenderableSet.Ref) !RenderableSet.Ref {
        std.debug.assert(pipeline_index < this.pipeline_buffer.len);
        std.debug.assert(this.pipeline_buffer[pipeline_index] != null);

        return try this.pipeline_buffer[pipeline_index].?.add_renderable(renderable);
    }

    fn pbody_create(this: *This, position: math.vec3, collider: Collider) !PhysicsBodySet.Ref {
        const key = try this.physics_bodies.add(
            PhysicsBody{
                .position = position,
                .velocity = math.vec3.zero(),
                .collider = collider,
            },
        );

        // unreachable because we LITERALLY JUST inserted and obtained the key
        return this.physics_bodies.to_ref(key) catch unreachable;
    }

    const DirtyObject = struct {
        old_position: Collider.AABB,
        dense_index: usize,
    };
    const This = @This();
};
