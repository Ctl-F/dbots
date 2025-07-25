const host = @import("host.zig");
const std = @import("std");

pub const Timer = struct {
    const This = @This();

    timestamp: u64,

    pub fn start() This {
        return This{
            .timestamp = host.sdl.sdl_GetPerformanceCounter(),
        };
    }

    pub fn restart(this: *This) void {
        this.timestamp = host.sdl.SDL_GetPerformanceCounter();
    }

    pub fn delta(this: *This) f64 {
        const current = host.sdl.SDL_GetPerformanceCounter();
        const dt = current - this.timestamp;
        this.timestamp = current;
        return @as(f64, @floatFromInt(dt)) / @as(f64, @floatFromInt(host.sdl.SDL_GetPerformanceFrequency()));
    }
};
