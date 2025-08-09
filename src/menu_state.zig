const std = @import("std");
const host = @import("host.zig");
const state = @import("statemachine.zig");
const assets = @import("assets.zig");
const math = @import("math.zig");
const entt = @import("entity.zig");
const ui = @import("ui.zig");

const appstate = @import("app_state.zig");

const AppStates = appstate.AppStates;
const AppGlobalContext = appstate.AppGlobalContext;
const State = appstate.State;

pub const MenuState = struct {
    scene: entt.Scene,
    controller: ?UiController,

    const UiController = struct {
        ux: ui,

        fn controller(this: *@This()) entt.Controller {
            return .{
                .context = this,
                .vtable = .{
                    .on_scene_load = load,
                    .on_scene_unload = unload,
                    .on_scene_prestep = prestep,
                    .on_scene_poststep = poststep,
                    .on_scene_predraw = predraw,
                    .on_scene_postdraw = postdraw,
                },
            };
        }

        fn load(scene: *entt.Scene, ctx: *anyopaque) !void {
            _ = scene;
            _ = ctx;
        }
        fn unload(scene: *entt.Scene, ctx: *anyopaque) !void {
            _ = scene;
            _ = ctx;
        }
        fn prestep(scene: *entt.Scene, ctx: *anyopaque, dt: f32) !void {
            _ = scene;
            _ = ctx;
            _ = dt;
        }
        fn poststep(scene: *entt.Scene, ctx: *anyopaque, dt: f32) !void {
            _ = scene;
            _ = ctx;
            _ = dt;
        }
        fn predraw(scene: *entt.Scene, ctx: *anyopaque) !void {
            _ = scene;
            _ = ctx;
        }
        fn postdraw(scene: *entt.Scene, ctx: *anyopaque, renderPass: *host.Pipeline.RenderPass) !void {
            const this: *UiController = @ptrCast(@alignCast(ctx));
            _ = scene;

            var uipass = try this.ux.pipeline.begin(.{
                .colorOp = .Load,
                .depthOp = null,
            }, renderPass.*);

            const viewport = host.viewport(f32);

            try this.ux.render_text_aligned(&uipass, .Title, viewport.w * 0.5, 10, .TopCenter, math.vec4.one());
            try this.ux.pipeline.end(&uipass);
        }
    };

    pub fn init() !@This() {
        var scene = try entt.Scene.init(.{
            .position = math.vec3.new(-10, -10, -10),
            .size = math.vec3.new(20, 20, 20),
        });

        try scene.resources.build_default_assets();

        var fmt = host.VertexFormat.begin();
        fmt.add(.Float3) catch unreachable;
        fmt.add(.Float3) catch unreachable;

        const pipelineConfig = host.PipelineConfig{
            .blend_mode = .Disabled,
            .depth_config = .{
                .test_enable = true, //TODO: Debug sdl assertion failure
                .write_enable = true,
            },
            .enable_culling = false,
            .fill_mode = .Fill,
            .vertex_format = fmt,
            .fragment_shader = scene.resources.get(assets.Shader, assets.Default.DebugShaderFragment).?,
            .vertex_shader = scene.resources.get(assets.Shader, assets.Default.DebugShaderVertex).?,
            .topology = .TriangleList,
        };

        const pipeline = try host.Pipeline.init(pipelineConfig);
        errdefer pipeline.free();

        var scenePipeline = try entt.ScenePipeline.init(
            pipeline,
            .{
                .colorOp = .{ .Clear = .{ 0.1, 0.2, 0.2, 1.0 } },
                .depthOp = null,
            },
        );
        errdefer scenePipeline.deinit();

        const viewport = host.viewport(f32);

        scene.add_pipeline(scenePipeline, 0);
        var this = @This(){ .scene = scene, .controller = null };

        this.controller = UiController{
            .ux = try ui.init(viewport.w, viewport.h, 0, 10, &this.scene.resources, assets.Default.FontXLarge, .English),
        };
        try this.controller.?.ux.language_pack.gen_textures(); // temporary

        _ = try this.scene.controllers.add(this.controller.?.controller());

        return this;
    }

    pub fn deinit(this: *@This()) void {
        this.controller.?.ux.deinit();
        this.scene.deinit();
    }

    pub fn vtable() State.VTable {
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
        std.debug.print("Menu State\n", .{});

        host.input().capture_mouse(false);
    }

    fn on_exit(ctx: *anyopaque, global: *AppGlobalContext, to: ?*State) !void {
        _ = ctx;
        _ = to;
        _ = global;

        host.input().capture_mouse(true);
    }

    fn on_step(ctx: *anyopaque, global: *AppGlobalContext, dt: f32) !AppStates {
        const this: *MenuState = @ptrCast(@alignCast(ctx));

        var input = host.input();

        if (input.close_condition) {
            global.close_trigger = true;
        }

        if (input.action_just_pressed(.Start)) {
            return AppStates.Game;
        }

        try this.scene.update(dt);
        try this.scene.render();

        return AppStates.None;
    }
};
