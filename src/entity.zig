const std = @import("std");
const host = @import("host.zig");
const math = @import("math.zig");
const camera = @import("camera.zig");
const assets = @import("assets.zig");

const containers = @import("containers.zig");

pub const ComponentID = usize;

const PhysicsBodySet = containers.SparseSet(PhysicsBody);
const RenderableSet = containers.SparseSet(StandardRenderable);
const GameObjectSet = containers.SparseSet(GameObject);
const SpatialTree = containers.FixedSpatialTree(GameObject, GameObject.get_aabb, 6);
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

    pub fn get_aabb(this: *GameObject) Collider.AABB {
        const body = this.body.get();

        return body.collider.get_aabb(body.position);
    }

    pub const VTable = struct {
        on_create: *const fn (base: *GameObject, scene: *Scene, context: *anyopaque) anyerror!void,
        on_destroy: *const fn (base: *GameObject, scene: *Scene, context: *anyopaque) void,
        on_step: *const fn (base: *GameObject, scene: *Scene, context: *anyopaque, dt: f32) anyerror!void,
    };

    pub fn create(this: *This, scene: *Scene) anyerror!void {
        return try this.vtable.on_create(this, scene, this.context);
    }
    pub fn destroy(this: *This, scene: *Scene) void {
        return this.vtable.on_destroy(this, scene, this.context);
    }
    pub fn step(this: *This, dt: f32, scene: *Scene) anyerror!void {
        return try this.vtable.on_step(this, scene, this.context, dt);
    }

    pub fn empty(body: PhysicsBodySet.Ref) This {
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

pub const Scene = struct {
    const This = @This();

    projection: math.mat4,
    view: math.mat4,

    active_objects: SpatialTree,
    inactive_objects: GameObjectSet, // TODO: Change to a SpatialTree mirroring the active_objects
    new_objects: GameObjectSet,
    dead_objects: GameObjectSet,
    renderables: RenderableSet,
    physics_bodies: PhysicsBodySet,
    resources: assets.SceneResources,

    pub fn init(boundry: containers.Dim3D) !This {
        var active_objects = try SpatialTree.init_capacity(host.MemAlloc, boundry, InitialCapacity);
        errdefer active_objects.deinit();

        var inactive_objects = try GameObjectSet.init_capacity(host.MemAlloc, InitialCapacity);
        errdefer inactive_objects.deinit();

        var dead_objects = try GameObjectSet.init_capacity(host.MemAlloc, InitialCapacity);
        errdefer dead_objects.deinit();

        var new_objects = try GameObjectSet.init_capacity(host.MemAlloc, InitialCapacity);
        errdefer new_objects.deinit();

        return This{
            .projection = math.mat4.identity(),
            .view = math.mat4.identity(),

            .active_objects = active_objects,
            .inactive_objects = inactive_objects,
            .dead_objects = dead_objects,
            .new_objects = new_objects,
            .renderables = RenderableSet.init(host.MemAlloc),
            .physics_bodies = PhysicsBodySet.init(host.MemAlloc),
            .resources = assets.SceneResources.init(host.MemAlloc),
        };
    }
    pub fn deinit(this: *This) void {
        for (this.active_objects.instances.items()) |*instance| {
            instance.destroy(this);
        }
        for (this.inactive_objects.items()) |*instance| {
            instance.destroy(this);
        }
        // should be empty but just in case
        for (this.dead_objects.items()) |*instance| {
            instance.destroy(this);
        }

        this.active_objects.deinit();
        this.dead_objects.deinit();
        this.inactive_objects.deinit();
        this.renderables.deinit();
        this.physics_bodies.deinit();
        this.resources.deinit();
    }
    pub fn update(this: *This, dt: f32) anyerror!void {
        // promote any new objects
        // this relies on GameObjects themselves being trivially copyable
        // TODO: The current setup of adding new objects and generally transfering
        // objects between sets (active/inactive/new/dead) won't work because the ref
        // is tied to the set. Meaning if the user has a GameObjectRef for a new_object
        // that ref will be invalid as soon as it gets promoted to active.
        // We could try to get around this by creating a sparse-set of refs and then returning that
        // key to the user. Then we would have the freedom to move objects around between sets. I don't like
        // that very much though because it introduces an EXTRA indirection to an already indirect system.
        // SparseSet: UserKey --> sparse_lookup --> item
        // SetKey: UserKey --> sparse_lookup(ref) --> sparse_lookup --> item
        //
        // User shouldn't need to store references for more than a frame. They aren't coding
        // the main loop of the game. They are coding the logic for each object type and then maybe
        // scene and event timings. Things work "in parallel" and together so as long as lookup is efficient
        // (spatial tree should help) then they should be looking up the data they need and obtaining references
        // that are valid for that frame. If an object MUST store a reference to the game object then they should
        // rethink the problem.

        try this.update_active_instances(dt);
    }
    pub fn render() !void {}

    fn update_active_instances(this: *This, delta: f32) anyerror!void {
        for (this.active_objects.instances.items()) |*obj| {
            try obj.step(delta, this);
        }
    }

    pub fn instance_create(this: *This, position: math.vec3, collider: Collider) !GameObjectSet.Ref {
        const body = try this.pbody_create(position, collider);
        const key = try this.new_objects.add(GameObject.empty(body));
        return this.new_objects.to_ref(key);
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
};
