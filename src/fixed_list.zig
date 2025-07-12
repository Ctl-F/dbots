const std = @import("std");

pub const ErrorSet = error{
    InsufficientMemory,
};

pub fn FixedList(comptime T: type, capacity: comptime_int) type {
    return struct {
        const This = @This();

        buffer: [capacity]T,
        items: []T,

        pub fn init() This {
            return This{
                .buffer = undefined,
                .items = &.{},
            };
        }

        pub fn add(this: *This, item: T) ErrorSet!void {
            if (this.items.len >= this.buffer.len) {
                return ErrorSet.InsufficientMemory;
            }

            const index = this.items.len;
            this.buffer[index] = item;
            this.items = this.buffer[0..(index + 1)];
        }

        pub fn reset(this: *This) void {
            this.items = &.{};
        }

        pub inline fn full(this: This) bool {
            return this.items.len == this.buffer.len;
        }

        pub inline fn empty(this: This) bool {
            return this.items.len == 0;
        }
    };
}
