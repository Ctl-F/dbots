const std = @import("std");
const host = @import("host.zig");
const timing = @import("timing.zig");
const aps = @import("app_state.zig");

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

    var appStateCtx = aps.AppGlobalContext.default();
    var states: aps.StatesContainer = undefined;

    var appState = try aps.make_machine(&states, &appStateCtx);
    defer aps.destroy_machine(&states, &appState);
    try appState.begin(aps.AppStates.Menu);

    var timer = timing.Timer.start();
    var input = host.input();
    while (!appStateCtx.close_trigger) {
        input.process_events();
        try appState.step(timer.delta(f32));
    }
}
