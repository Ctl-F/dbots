const std = @import("std");

pub fn SparseSet(comptime T: type) type {
    return struct {
        const This = @This();

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

        pub fn deinit(this: *This) void {
            this.sparse.deinit();
            this.holes.deinit();
            this.dense.deinit();
            this.back_map.deinit();
        }

        pub fn add(this: *This, entity: T) !usize {
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

        pub fn get(this: *This, index: usize) ?T {
            if (this.get_ptr(index)) |ptr| {
                return ptr.*;
            }
            return null;
        }

        pub fn get_ptr(this: *This, index: usize) ?*T {
            if (!this.contains(index)) return null;

            const dense_index = this.sparse.items[index].?;

            std.debug.assert(dense_index < this.dense.items.len);

            return &this.dense.items[dense_index];
        }

        pub inline fn contains(this: This, index: usize) bool {
            return index < this.sparse.items.len and this.sparse.items[index] != null;
        }

        pub fn remove(this: *This, index: usize) void {
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
