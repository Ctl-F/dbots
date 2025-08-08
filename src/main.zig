const std = @import("std");

const host = @import("host.zig");
const assets = @import("assets.zig");
const ett = @import("entity.zig");
const math = @import("math.zig");
const state = @import("statemachine.zig");
const timing = @import("timing.zig");

const AppStates = enum {
    None,
    Menu,
    Game,
    Paused,
};

const AppGlobalContext = struct {
    close_trigger: bool,
};

const AppStateMachine = state.StateMachine(AppGlobalContext, AppStates, .None);
const State = AppStateMachine.State;

const MenuState = struct {
    scene: ett.Scene,

    pub fn init() !@This() {
        const scene = try ett.Scene.init(.{
            .position = math.vec3.new(-10, -10, -10),
            .size = math.vec3.new(20, 20, 20),
        });

        try scene.resources.build_default_assets();

        var fmt = host.VertexFormat.begin();
        fmt.add(.Float3) catch unreachable;
        fmt.add(.Float3) catch unreachable;

        const pipelineConfig = host.PipelineConfig{
            .blend_mode = .Disabled,
            .depth_config = null,
            .enable_culling = false,
            .fill_mode = .Fill,
            .vertex_format = fmt,
            .fragment_shader = scene.resources.get(assets.Shader, assets.Default.DebugShaderFragment).?,
            .vertex_shader = scene.resources.get(assets.Shader, assets.Default.DebugShaderVertex).?,
            .topology = .TriangleList,
        };

        const pipeline = try host.Pipeline.init(pipelineConfig);
        errdefer pipeline.free();

        var scenePipeline = try ett.ScenePipeline.init(
            pipeline,
            .{
                .colorOp = .{ .Clear = .{ 0.1, 0.2, 0.2, 1.0 } },
                .depthOp = null,
            },
        );
        errdefer scenePipeline.deinit();

        scene.add_pipeline(scenePipeline, 0);
        return @This(){
            .scene = scene,
        };
    }

    pub fn deinit(this: *@This()) void {
        this.scene.deinit();
    }

    fn vtable() State.VTable {
        return .{
            .on_enter = on_enter,
            .on_exit = on_exit,
            .on_step = on_step,
        };
    }

    fn on_enter(ctx: *anyopaque, global: *AppGlobalContext, from: ?*State) !void {
        _ = from;
        _ = ctx;
        _ = global;

        //global.current_scene = &@as(*MenuState, @ptrCast(@alignCast(ctx))).scene;

        std.debug.print("Menu State\n", .{});
    }

    fn on_exit(ctx: *anyopaque, global: *AppGlobalContext, to: ?*State) !void {
        _ = ctx;
        _ = to;

        global.current_scene = null;
    }

    fn on_step(ctx: *anyopaque, global: *AppGlobalContext, dt: f32) !AppStates {
        const this: *MenuState = @ptrCast(@alignCast(ctx));

        var input = host.input();
        input.process_events();

        if (input.close_condition) {
            global.close_trigger = true;
        }

        if (input.action_just_pressed(.Inventory)) {
            return AppStates.Game;
        }

        try this.scene.update(dt);
        try this.scene.render();

        return AppStates.None;
    }
};

const GameState = struct {
    fn vtable() State.VTable {
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

        var input = host.input();
        input.process_events();

        if (input.close_condition) {
            global.close_trigger = true;
        }

        if (input.action_just_pressed(.Pause)) {
            return AppStates.Paused;
        }

        try global.current_scene.update(dt);
        try global.current_scene.render();

        return AppStates.None;
    }
};

const PauseState = struct {
    fn vtable() State.VTable {
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
        std.debug.print("Paused State\n", .{});

        host.input().capture_mouse(false);
    }

    fn on_exit(ctx: *anyopaque, global: *AppGlobalContext, to: ?*State) !void {
        _ = ctx;
        _ = global;
        _ = to;

        host.input().capture_mouse(true);
    }

    fn on_step(ctx: *anyopaque, global: *AppGlobalContext, dt: f32) !AppStates {
        _ = ctx;
        _ = dt;

        var input = host.input();
        input.process_events();

        if (input.close_condition) {
            global.close_trigger = true;
        }

        if (input.action_just_pressed(.Pause)) {
            return AppStates.Game;
        }

        return AppStates.None;
    }
};

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

    var appStateCtx = AppGlobalContext{
        .close_trigger = false,
    };

    var appState = AppStateMachine.init(host.MemAlloc, &appStateCtx);
    defer appState.deinit();

    var menuState = try MenuState.init();
    defer menuState.deinit();

    var gameState = GameState{};
    var pauseState = PauseState{};

    try appState.add_state(State{
        .id = AppStates.Menu,
        .context = &menuState,
        .vtable = MenuState.vtable(),
    });
    try appState.add_state(State{
        .id = AppStates.Game,
        .context = &gameState,
        .vtable = GameState.vtable(),
    });
    try appState.add_state(State{
        .id = AppStates.Paused,
        .context = &pauseState,
        .vtable = PauseState.vtable(),
    });

    var timer = timing.Timer.start();
    try appState.begin(AppStates.Menu);
    while (!appStateCtx.close_trigger) {
        try appState.step(timer.delta(f32));
    }
}
