const std = @import("std");

const host = @import("host.zig");
const assets = @import("assets.zig");
const ett = @import("entity.zig");
const math = @import("math.zig");
const state = @import("statemachine.zig");
const timing = @import("timing.zig");

const AppStates = enum {
    Menu,
    Game,
    Paused,
};

const AppGlobalContext = struct {
    close_trigger: bool,
};

const AppStateInfo = union(AppStates) {
    const This = @This();

    Menu: MenuState,
    Game: GameState,
    Paused: PausedState,

    pub const MenuState = struct {
        pub fn construct(ctx: *AppGlobalContext) !@This() {
            _ = ctx;
            return @This(){};
        }
        pub fn destroy(this: @This()) void {
            _ = this;
        }
        pub fn on_enter(this: *This(), from: ?*AppStateInfo, ctx: *AppGlobalContext) !void {
            _ = this;
            _ = from;
            _ = ctx;
        }
        pub fn step(this: *This(), ctx: *AppGlobalContext) !?AppStates {
            _ = this;
            _ = ctx;

            host.input().process_events();

            if (host.input().action_just_pressed(.Main)) {
                return AppStates.Game;
            }

            return null;
        }
        pub fn on_exit(this: *This(), to: ?*AppStateInfo, ctx: *AppGlobalContext) !void {
            _ = this;
            _ = to;
            _ = ctx;
        }
    };

    pub const PausedState = struct {
        pub fn construct(ctx: *AppGlobalContext) !@This() {
            _ = ctx;
            return @This(){};
        }
        pub fn destroy(this: @This()) void {
            _ = this;
        }
        pub fn on_enter(this: *This(), from: ?*AppStateInfo, ctx: *AppGlobalContext) !void {
            _ = this;
            _ = from;
            _ = ctx;
            host.input().capture_mouse(false);
            std.debug.print("Paused\n", .{});
        }
        pub fn step(this: *This(), ctx: *AppGlobalContext) !?AppStates {
            _ = this;
            _ = ctx;

            host.input().process_events();

            if (host.input().action_just_pressed(.Pause)) {
                return AppStates.Game;
            }

            return null;
        }
        pub fn on_exit(this: *This(), to: ?*AppStateInfo, ctx: *AppGlobalContext) !void {
            _ = this;
            _ = to;
            _ = ctx;
            host.input().capture_mouse(true);
            std.debug.print("Unpaused\n", .{});
        }
    };

    pub const GameState = struct {
        pub fn construct(ctx: *AppGlobalContext) !@This() {
            _ = ctx;
            return @This(){};
        }
        pub fn destroy(this: @This()) void {
            _ = this;
        }
        pub fn on_enter(this: *This(), from: ?*AppStateInfo, ctx: *AppGlobalContext) !void {
            _ = this;
            _ = from;
            _ = ctx;
        }
        pub fn step(this: *This(), ctx: *AppGlobalContext) !?AppStates {
            _ = this;
            _ = ctx;

            host.input().process_events();

            if (host.input().action_just_pressed(.Pause)) {
                return AppStates.Paused;
            }

            return null;
        }
        pub fn on_exit(this: *This(), to: ?*AppStateInfo, ctx: *AppGlobalContext) !void {
            _ = this;
            _ = to;
            _ = ctx;
        }
    };
};

const AppStateMachine = state.StateMachine(AppStateInfo, AppGlobalContext);

pub fn main() !void {
    try host.init(.{
        .display = .{
            .width = 1280,
            .height = 960,
            .monitor = null,
            .vsync = false,
        },
        .title = "Death Bots",
    });
    defer host.deinit();

    host.input_mode(.Keyboard);

    var global_context = AppGlobalContext{
        .close_trigger = false,
    };
    var appStateMachine = AppStateMachine.init(AppStates.Menu, &global_context);
    defer appStateMachine.deinit();

    while (!global_context.close_trigger) {
        try appStateMachine.step(&global_context);
    }
}
