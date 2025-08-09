const std = @import("std");
const host = @import("host.zig");
const state = @import("statemachine.zig");
const assets = @import("assets.zig");
const math = @import("math.zig");
const entt = @import("entity.zig");

const appstate = @import("app_state.zig");

const AppStates = appstate.AppStates;
const AppGlobalContext = appstate.AppGlobalContext;
const State = appstate.State;

pub const GameState = struct {
    pub fn vtable() State.VTable {
        return .{
            .on_enter = on_enter,
            .on_exit = on_exit,
            .on_step = on_step,
        };
    }

    fn on_enter(ctx: *anyopaque, global: *AppGlobalContext, from: ?*State) !void {
        _ = ctx;
        _ = global;
        _ = from;
        std.debug.print("Game State\n", .{});
    }

    fn on_exit(ctx: *anyopaque, global: *AppGlobalContext, to: ?*State) !void {
        _ = ctx;
        _ = global;
        _ = to;
    }

    fn on_step(ctx: *anyopaque, global: *AppGlobalContext, dt: f32) !AppStates {
        _ = ctx;
        _ = dt;
        var input = host.input();

        if (input.close_condition) {
            global.close_trigger = true;
        }

        if (input.action_just_pressed(.Pause)) {
            return AppStates.Paused;
        }

        return AppStates.None;
    }
};
