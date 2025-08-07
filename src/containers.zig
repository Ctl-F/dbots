const std = @import("std");
const math = @import("math.zig");
const host = @import("host.zig");

pub const SparseKey = usize;

pub fn SparseSet(comptime T: type) type {
    return struct {
        const This = @This();

        pub const Key = SparseKey;
        pub const Ref = struct {
            parent: *SparseSet(T),
            key: Key,

            pub fn get(this: @This()) *T {
                return this.parent.get_ptr(this.key).?;
            }
        };

        sparse: std.ArrayList(?usize), // holds index of item in dense array
        holes: std.ArrayList(usize), // stack of empty sparse slots to avoid a linear search
        dense: std.ArrayList(T), // actual array of items
        back_map: std.ArrayList(usize), // given dense index, this should point to the sparse index that points back to the dense item
        // needed for efficient swap logic

        pub fn init(allocator: std.mem.Allocator) This {
            return This{
                .sparse = std.ArrayList(?usize).init(allocator),
                .holes = std.ArrayList(usize).init(allocator),
                .dense = std.ArrayList(T).init(allocator),
                .back_map = std.ArrayList(usize).init(allocator),
            };
        }

        pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !This {
            return This{
                .sparse = try std.ArrayList(?usize).initCapacity(allocator, capacity),
                .holes = try std.ArrayList(usize).initCapacity(allocator, capacity),
                .dense = try std.ArrayList(T).initCapacity(allocator, capacity),
                .back_map = try std.ArrayList(usize).initCapacity(allocator, capacity),
            };
        }

        pub fn deinit(this: *This) void {
            this.sparse.deinit();
            this.holes.deinit();
            this.dense.deinit();
            this.back_map.deinit();
        }

        pub fn add(this: *This, entity: T) !Key {
            // we don't allow holes in the dense array so insert should
            // literally just be an append to the dense array
            const dense_index = this.dense.items.len;
            try this.dense.append(entity);
            errdefer _ = this.dense.pop();

            const sparse_index = try this.find_free_sparse_slot();

            try this.back_map.append(sparse_index);
            errdefer _ = this.back_map.pop(); // realistically not necessary unless we add additional failing logic after this line

            // sanity check
            std.debug.assert(this.back_map.items.len == this.dense.items.len);

            this.sparse.items[sparse_index] = dense_index;
            return sparse_index;
        }

        pub fn get(this: *This, index: Key) ?T {
            if (this.get_ptr(index)) |ptr| {
                return ptr.*;
            }
            return null;
        }

        pub fn get_ptr(this: *This, index: Key) ?*T {
            if (!this.contains(index)) return null;

            const dense_index = this.sparse.items[index].?;

            std.debug.assert(dense_index < this.dense.items.len);

            return &this.dense.items[dense_index];
        }

        pub fn to_ref(this: *This, index: Key) !Ref {
            if (this.contains(index)) {
                return Ref{ .parent = this, .key = index };
            }
            return error.InvalidKey;
        }

        pub inline fn contains(this: This, index: Key) bool {
            return index < this.sparse.items.len and this.sparse.items[index] != null;
        }

        pub fn find_value(this: This, value: T) ?Key {
            for (0..this.dense.items.len) |idx| {
                if (this.dense.items[idx] == value) {
                    return this.back_map.items[idx];
                }
            }
            return null;
        }

        pub fn remove(this: *This, index: Key) void {
            if (!this.contains(index)) {
                return;
            }

            const dense_index_to_remove = this.sparse.items[index] orelse unreachable; // this would be a sign that we're trying to remove something that doesn't exist. Flag this as a probably bug
            const last_dense_item = this.dense.items.len - 1;
            if (dense_index_to_remove < last_dense_item) {
                const second_sparse_index = this.back_map.items[last_dense_item];

                // perform a swap
                std.mem.swap(T, this.dense.items[dense_index_to_remove], this.dense.items[last_dense_item]);
                std.mem.swap(usize, this.back_map.items[dense_index_to_remove], this.back_map.items[last_dense_item]);

                // update the pointer to the live item that got moved
                this.sparse.items[second_sparse_index] = dense_index_to_remove;

                // now, the item to remove should be the last item in the dense set
                // and it's paired back_mapping should be with it
            }

            // now the item to remove is at the end of the array we can pop it off
            _ = this.back_map.pop();
            _ = this.dense.pop();

            std.debug.assert(this.dense.items.len == this.back_map.items.len);

            // update the sparse set to be empty
            this.sparse.items[index] = null;

            // record the hole in the sparse set for easy reclaming
            this.holes.append(index) catch unreachable; // if this fails, there's nothing much we can honestly do within the scope of our program. for now just crash until I think of a better solution

            // done?
        }

        pub fn items(this: *This) []T {
            return this.dense.items;
        }

        pub inline fn empty(this: This) bool {
            return this.dense.items.len == 0;
        }

        fn find_free_sparse_slot(this: *This) !usize {
            return this.holes.pop() orelse Append: {
                // since we're storing null entries in the holes stack
                // we don't have to actually linearly search for a null slot in the
                // sparse array. If we hit this point we can just append a new slot
                const index = this.sparse.items.len;
                try this.sparse.append(0);
                break :Append index;
            };
        }
    };
}

pub const Dim3D = struct {
    position: math.vec3,
    size: math.vec3,

    pub fn debug_render(this: Dim3D, renderPass: *host.Pipeline.RenderPass, color: math.vec3) !void {
        try host.debug_pipeline_add(renderPass, this.position.data, this.size.data, color.data);
    }

    pub inline fn overlaps(this: Dim3D, other: Dim3D) bool {
        const this_pos2 = this.position.add(this.size);
        const other_pos2 = other.position.add(other.size);

        return bbox_axis_check(this.position.x(), this_pos2.x(), other.position.x(), other_pos2.x()) and
            bbox_axis_check(this.position.y(), this_pos2.y(), other.position.y(), other_pos2.y()) and
            bbox_axis_check(this.position.z(), this_pos2.z(), other.position.z(), other_pos2.z());
    }

    pub inline fn contains(this: Dim3D, other: Dim3D) bool {
        const this_pos2 = this.position.add(this.size);
        const other_pos2 = other.position.add(other.size);

        return bbox_axis_contains(this.position.x(), this_pos2.x(), other.position.x(), other_pos2.x()) and
            bbox_axis_contains(this.position.y(), this_pos2.y(), other.position.y(), other_pos2.y()) and
            bbox_axis_contains(this.position.z(), this_pos2.z(), other.position.z(), other_pos2.z());
    }

    inline fn bbox_axis_check(min_a: f32, max_a: f32, min_b: f32, max_b: f32) bool {
        return (min_a <= max_b) and (max_a >= min_b);
    }

    inline fn bbox_axis_contains(min_a: f32, max_a: f32, min_b: f32, max_b: f32) bool {
        return (min_a <= min_b) and (max_a >= max_b);
    }
};

const __DebugColors = [_]math.vec3{
    .{ .data = .{ 1, 1, 1 } },
    .{ .data = .{ 1, 0, 0 } },
    .{ .data = .{ 0, 1, 0 } },
    .{ .data = .{ 0, 0, 1 } },
    .{ .data = .{ 1, 0, 1 } },
    .{ .data = .{ 1, 1, 0 } },
    .{ .data = .{ 0, 1, 1 } },
    .{ .data = .{ 1, 0, 1 } },
};

pub fn FixedSpatialTree(comptime T: type, comptime interface: *const fn (*const T) Dim3D, comptime nest_limit: usize) type {
    return struct {
        const This = @This();

        const Bucket = struct {
            field: Dim3D,
            instances: std.AutoHashMap(usize, bool),

            inline fn left(this: usize) usize {
                return 2 * this + 1;
            }
            inline fn right(this: usize) usize {
                return 2 * this + 2;
            }
        };

        instances: SparseSet(T),
        buckets: [(std.math.powi(usize, 2, nest_limit) catch unreachable) - 1]Bucket = undefined,

        pub fn debug_draw(this: This, renderPass: *host.Pipeline.RenderPass) !void {
            var idx: usize = 0;
            for (this.buckets) |bucket| {
                try bucket.field.debug_render(renderPass, __DebugColors[idx]);
                idx = (idx + 1) % __DebugColors.len;
            }
        }

        pub fn debug_display(this: This, writer: anytype) void {
            write_bucket_json(writer, &this.buckets, 0, 0) catch return;
        }

        fn write_bucket_json(writer: anytype, buckets: []const Bucket, index: usize, depth: usize) !void {
            if (index >= buckets.len) {
                try writer.writeAll("null");
                return;
            }

            const indent = struct {
                pub fn write(w: anytype, d: usize) !void {
                    try w.writeByteNTimes(' ', d * 4);
                }
            };

            const bucket = buckets[index];
            try writer.writeAll("{\n");

            try indent.write(writer, depth + 1);
            try writer.writeAll("\"position\": ");
            try write_vec3_json(writer, bucket.field.position);
            try writer.writeAll(",\n");

            try indent.write(writer, depth + 1);
            try writer.writeAll("\"size\": ");
            try write_vec3_json(writer, bucket.field.size);
            try writer.writeAll(",\n");

            const left_index = 2 * index + 1;
            const right_index = 2 * index + 2;

            try indent.write(writer, depth + 1);
            try writer.writeAll("\"left\": ");
            try write_bucket_json(writer, buckets, left_index, depth + 1);
            try writer.writeAll(",\n");

            try indent.write(writer, depth + 1);
            try writer.writeAll("\"right\": ");
            try write_bucket_json(writer, buckets, right_index, depth + 1);
            try writer.writeAll("\n");

            try indent.write(writer, depth);
            try writer.writeAll("}");
        }

        fn write_vec3_json(writer: anytype, vec: math.vec3) !void {
            try writer.print("[{d:.2}, {d:.2}, {d:.2}]", .{ vec.x(), vec.y(), vec.z() });
        }

        pub fn init(allocator: std.mem.Allocator, area: Dim3D) This {
            var this = This{
                .instances = SparseSet(T).init(allocator),
                .buckets = undefined,
            };

            this.buckets[0] = Bucket{
                .field = area,
                .instances = std.AutoHashMap(usize, bool).init(allocator),
            };
            this.compute_children(0, 0) catch unreachable;

            return this;
        }

        pub fn init_capacity(allocator: std.mem.Allocator, area: Dim3D, capacity: usize) !This {
            var this = This{
                .instances = try SparseSet(T).init_capacity(allocator, capacity),
                .buckets = undefined,
            };

            this.buckets[0] = Bucket{
                .field = area,
                .instances = std.AutoHashMap(usize, bool).init(allocator),
            };

            this.compute_children(0, 0) catch unreachable;

            return this;
        }

        pub fn deinit(this: *This) void {
            for (&this.buckets) |*bucket| {
                bucket.instances.deinit();
            }
            this.instances.deinit();
        }

        fn compute_children(this: *This, index: usize, iteration: usize) !void {
            if (iteration + 1 >= nest_limit) return;

            const parent = this.buckets[index];

            if (parent.field.size.x() == 0 or parent.field.size.y() == 0 or parent.field.size.z() == 0) {
                return error.ZeroWidthField;
            }

            var left = &this.buckets[Bucket.left(index)];
            var right = &this.buckets[Bucket.right(index)];

            split(parent.field, &left.field, &right.field);

            left.instances = std.AutoHashMap(usize, bool).init(parent.instances.allocator);
            right.instances = std.AutoHashMap(usize, bool).init(parent.instances.allocator);

            try this.compute_children(Bucket.left(index), iteration + 1);
            try this.compute_children(Bucket.right(index), iteration + 1);
        }

        fn split(bucket: Dim3D, left: *Dim3D, right: *Dim3D) void {
            const max = @max(bucket.size.x(), bucket.size.y(), bucket.size.z());

            if (bucket.size.x() == max) {
                // split along x
                const half_size_x = bucket.size.x() / 2;
                const half_size = math.vec3.new(half_size_x, bucket.size.y(), bucket.size.z());

                left.position = bucket.position;
                left.size = half_size;

                right.position = bucket.position.add(math.vec3.new(half_size_x, 0, 0));
                right.size = half_size;
            } else if (bucket.size.y() == max) {
                // split along y
                const half_size_y = bucket.size.y() / 2;
                const half_size = math.vec3.new(bucket.size.x(), half_size_y, bucket.size.z());

                left.position = bucket.position;
                left.size = half_size;

                right.position = bucket.position.add(math.vec3.new(0, half_size_y, 0));
                right.size = half_size;
            } else {
                // split along z
                const half_size_z = bucket.size.z() / 2;
                const half_size = math.vec3.new(bucket.size.x(), bucket.size.y(), half_size_z);

                left.position = bucket.position;
                left.size = half_size;

                right.position = bucket.position.add(math.vec3.new(0, 0, half_size_z));
                right.size = half_size;
            }
        }

        pub fn insert(this: *This, instance: T) !usize {
            const key = try this.instances.add(instance);

            const bbox = interface(&instance);

            const bucket = this.find_bucket(0, bbox);
            try bucket.instances.put(key, 1);

            return key;
        }

        pub fn remove(this: *This, instance: T) void {
            const key = this.instances.find_value(instance) orelse return;

            const bbox = interface(&instance);
            var bucket = this.find_bucket(0, bbox);

            // since we have a KEY then we should also never fail
            // to find the bucket. Hence the sanity check
            std.debug.assert(bucket.instances.contains(key));

            bucket.instances.remove(key);
            this.instances.remove(key);
        }

        pub fn find(this: This, results: []?*T, area: Dim3D) usize {
            return this.find_in_bucket(results, area, 0);
        }

        /// searches the bucket for instances that overlap with area
        /// returns number of instances added to results
        fn find_in_bucket(this: This, results: []?*T, area: Dim3D, bucket: usize) usize {
            const this_bucket = this.buckets[bucket];

            if (results.len == 0) {
                return 0;
            }

            if (bucket == 0 and !area.overlaps(bucket)) {
                return 0;
            }

            if (area.contains(this_bucket.field)) {
                // add everything since it's full contained
                return this.dump_bucket(results, bucket);
            }

            var iterator = this_bucket.instances.iterator();
            var index: usize = 0;

            // add all of my instances that overlap with area
            while (iterator.next()) |kv| {
                if (index >= results.len) return index;

                const key = kv.key_ptr.*;
                const instance = this.instances.get_ptr(key).?;

                // possible improvement: @inlineCall(interface, instance)
                if (area.overlaps(interface(instance))) {
                    results[index] = instance;
                    index += 1;
                }
            }

            const bLeft = Bucket.left(bucket);
            const bRight = Bucket.right(bucket);

            if (bLeft < this.buckets.len and index < results.len and area.overlaps(this.buckets[bLeft])) {
                index += this.find_in_bucket(this, results[index..], area, bLeft);
            }

            if (bRight < this.buckets.len and index < results.len and area.overlaps(this.buckets[bRight])) {
                index += this.find_in_bucket(this, results[index..], area, bRight);
            }

            return index;
        }

        pub const RaycastResult = struct {
            instance: ?*T,
            distance: ?f32,
        };

        pub fn raycast(this: This, ray_origin: math.vec3, ray_dir: math.vec3) RaycastResult {
            var result: RaycastResult = .{ .instance = null, .distance = null };
            this.raycast_bucket(ray_origin, ray_dir.norm(), 0, &result);
            return result;
        }

        fn raycast_bucket(this: This, origin: math.vec3, dir: math.vec3, bucket: usize, best_result: *RaycastResult) void {
            if (bucket >= this.buckets.len) return;

            const this_bucket = &this.buckets[bucket];

            if (!ray_intersect_aabb(origin, dir, this_bucket.field)) {
                return; // skip bucket entirely
            }
            var iterator = this_bucket.instances.iterator();

            while (iterator.next()) |kv| {
                const key = kv.key_ptr.*;
                const instance = this.instances.get_ptr(key).?;

                const aabb = interface(instance);
                const info = ray_intersect_aabb_info(origin, dir, aabb);
                if (info.intersect) {
                    const dist = info.distance;
                    if (best_result.distance == null or dist < best_result.distance.?) {
                        best_result.instance = instance;
                        best_result.distance = dist;
                    }
                }
            }

            const bLeft = Bucket.Left(bucket);
            const bRight = Bucket.right(bucket);

            //Improvements:
            // Return a list of results sorted by distance
            // check buckets in order of closest to furthest

            if (bLeft < this.buckets.len) {
                this.raycast_bucket(origin, dir, bLeft, best_result);
            }

            if (bRight < this.buckets.len) {
                this.raycast_bucket(origin, dir, bRight, best_result);
            }
        }

        const RayIntersectInfo = struct { intersect: bool, distance: f32 };

        fn ray_intersect_aabb_info(origin: math.vec3, dir: math.vec3, aabb: Dim3D) RayIntersectInfo {
            const inv_dir = math.vec3.one().div(dir);

            const min = aabb.position;
            const max = aabb.position.add(aabb.size);

            const t1 = (min.x() - origin.x()) * inv_dir.x();
            const t2 = (max.x() - origin.x()) * inv_dir.x();
            const t3 = (min.y() - origin.y()) * inv_dir.y();
            const t4 = (max.y() - origin.y()) * inv_dir.y();
            const t5 = (min.z() - origin.z()) * inv_dir.z();
            const t6 = (max.z() - origin.z()) * inv_dir.z();

            const tmin = @max(@min(t1, t2), @min(t3, t4), @min(t5, t6));
            const tmax = @min(@max(t1, t2), @max(t3, t4), @max(t5, t6));

            return .{ .intersect = tmax >= @max(tmin, 0.0), .distance = @max(tmin, 0.0) };
        }

        fn ray_distance_to_aabb(origin: math.vec3, dir: math.vec3, aabb: Dim3D) f32 {
            const inv_dir = math.vec3.one().div(dir);

            const min = aabb.position;
            const max = aabb.position.add(aabb.size);

            const t1 = (min.x() - origin.x()) * inv_dir.x();
            const t2 = (max.x() - origin.x()) * inv_dir.x();
            const t3 = (min.y() - origin.y()) * inv_dir.y();
            const t4 = (max.y() - origin.y()) * inv_dir.y();
            const t5 = (min.z() - origin.z()) * inv_dir.z();
            const t6 = (max.z() - origin.z()) * inv_dir.z();

            const tmin = @max(@min(t1, t2), @min(t3, t4), @min(t5, t6));
            return @max(tmin, 0.0);
        }

        /// dir must be normalized
        fn ray_intersect_aabb(origin: math.vec3, dir: math.vec3, aabb: Dim3D) bool {
            const inv_dir = math.vec3.one().div(dir);

            const min = aabb.position;
            const max = aabb.position.add(aabb.size);

            const t1 = (min.x() - origin.x()) * inv_dir.x();
            const t2 = (max.x() - origin.x()) * inv_dir.x();
            const t3 = (min.y() - origin.y()) * inv_dir.y();
            const t4 = (max.y() - origin.y()) * inv_dir.y();
            const t5 = (min.z() - origin.z()) * inv_dir.z();
            const t6 = (max.z() - origin.z()) * inv_dir.z();

            const tmin = @max(@min(t1, t2), @min(t3, t4), @min(t5, t6));
            const tmax = @min(@max(t1, t2), @max(t3, t4), @max(t5, t6));

            return tmax >= @max(tmin, 0.0);
        }

        fn dump_bucket(this: This, results: []?*T, bucket: usize) usize {
            const this_bucket = this.buckets[bucket];
            var iterator = this_bucket.instances.iterator();
            var index: usize = 0;

            while (iterator.next()) |kv| {
                if (index >= results.len) return index;

                const key = kv.key_ptr.*;
                results[index] = this.instances.get_ptr(key).?;
                index += 1;
            }

            const bLeft = Bucket.left(bucket);
            const bRight = Bucket.right(bucket);

            if (index < results.len and bLeft < this.buckets.len) {
                index += this.dump_bucket(results[index..], bLeft);
            }
            if (index < results.len and bRight < this.buckets.len) {
                index += this.dump_bucket(results[index..], bRight);
            }

            return index;
        }

        fn find_bucket(this: *This, bucket: usize, dim: Dim3D) *Bucket {
            const ileft = Bucket.left(bucket);
            const iright = Bucket.right(bucket);

            if (ileft >= this.buckets.len or iright >= this.buckets.len) return &this.buckets[bucket];

            const left = &this.buckets[ileft];
            const right = &this.buckets[iright];

            if (left.field.contains(dim)) {
                return this.find_bucket(ileft, dim) orelse &this.buckets[bucket];
            }

            if (right.field.contains(dim)) {
                return this.find_bucket(iright, dim) orelse &this.buckets[bucket];
            }

            return &this.buckets[bucket];
        }
    };
}
