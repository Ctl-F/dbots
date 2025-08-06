const host = @import("host.zig");
const std = @import("std");

pub const Timer = struct {
    const This = @This();

    timestamp: u64,

    pub fn start() This {
        return This{
            .timestamp = host.sdl.SDL_GetPerformanceCounter(),
        };
    }

    pub fn restart(this: *This) void {
        this.timestamp = host.sdl.SDL_GetPerformanceCounter();
    }

    pub fn delta(this: *This, comptime T: type) T {
        if (T != f32 and T != f64 and T != f128) {
            @compileError("Invalid type for Timer.delta. Expected f32/f64/f128 - Got: " ++ @typeName(T));
        }

        const current = host.sdl.SDL_GetPerformanceCounter();
        const dt = current - this.timestamp;
        this.timestamp = current;
        return @as(T, @floatFromInt(dt)) / @as(T, @floatFromInt(host.sdl.SDL_GetPerformanceFrequency()));
    }
};
