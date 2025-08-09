const std = @import("std");
const host = @import("host.zig");
const state = @import("statemachine.zig");
const assets = @import("assets.zig");
const math = @import("math.zig");
const entt = @import("entity.zig");

pub const AppStates = enum {
    None,
    Menu,
    Game,
    Paused,
};

pub const AppGlobalContext = struct {
    pub fn default() @This() {
        return .{
            .close_trigger = false,
        };
    }

    close_trigger: bool,
};

pub const AppStateMachine = state.StateMachine(AppGlobalContext, AppStates, .None);
pub const State = AppStateMachine.State;

pub const GameState = @import("game_state.zig").GameState;
pub const MenuState = @import("menu_state.zig").MenuState;
pub const PauseState = @import("pause_state.zig").PauseState;

pub const StatesContainer = struct {
    menu_state: MenuState,
    game_state: GameState,
    pause_state: PauseState,
};

///states should be undefined, it's just to properly store things in a good lifetime
pub fn make_machine(states: *StatesContainer, ctx: *AppGlobalContext) !AppStateMachine {
    states.menu_state = try MenuState.init();
    errdefer states.menu_state.deinit();

    states.game_state = GameState{};
    states.pause_state = PauseState{};

    var machine = AppStateMachine.init(host.MemAlloc, ctx);
    errdefer machine.deinit();

    try machine.add_state(State{
        .id = AppStates.Menu,
        .context = &states.menu_state,
        .vtable = MenuState.vtable(),
    });
    try machine.add_state(State{
        .id = AppStates.Game,
        .context = &states.game_state,
        .vtable = GameState.vtable(),
    });
    try machine.add_state(State{
        .id = AppStates.Paused,
        .context = &states.pause_state,
        .vtable = PauseState.vtable(),
    });

    return machine;
}

pub fn destroy_machine(states: *StatesContainer, machine: *AppStateMachine) void {
    machine.deinit();
    states.menu_state.deinit();
}
