const std = @import("std");
const host = @import("host.zig");
const sdl = host.sdl;

const This = @This();

close_condition: bool,
mode: Mode,
frame: [@intFromEnum(Actions.MAX_INPUT)]bool,
last_frame: [@intFromEnum(Actions.MAX_INPUT)]bool,

mouse_x_previous: f32,
mouse_y_previous: f32,
mouse_x: f32,
mouse_y: f32,
mouse_x_rel: f32,
mouse_y_rel: f32,

pub fn init(mode: Mode) This {
    _ = sdl.SDL_HideCursor();
    if (mode == .Keyboard) {
        _ = sdl.SDL_SetWindowRelativeMouseMode(host.window(), true);
    } else {
        _ = sdl.SDL_SetWindowRelativeMouseMode(host.window(), false);
    }

    return This{
        .close_condition = false,
        .mode = mode,
        .frame = [_]bool{false} ** @intFromEnum(Actions.MAX_INPUT),
        .last_frame = [_]bool{false} ** @intFromEnum(Actions.MAX_INPUT),
        .mouse_x = 0,
        .mouse_x_previous = 0,
        .mouse_x_rel = 0,
        .mouse_y = 0,
        .mouse_y_previous = 0,
        .mouse_y_rel = 0,
    };
}

pub fn capture_mouse(this: This, capture: bool) void {
    _ = this;
    _ = sdl.SDL_SetWindowRelativeMouseMode(host.window(), capture);
}

pub inline fn should_close(this: This) bool {
    return this.close_condition;
}

pub fn action_pressed(this: This, action: Actions) bool {
    std.debug.assert(action != .MAX_INPUT);
    return this.frame[@intFromEnum(action)];
}

pub fn action_just_pressed(this: This, action: Actions) bool {
    std.debug.assert(action != .MAX_INPUT);

    return this.frame[@intFromEnum(action)] and !this.last_frame[@intFromEnum(action)];
}

pub fn action_released(this: This, action: Actions) bool {
    std.debug.assert(action != .MAX_INPUT);

    return !this.frame[@intFromEnum(action)];
}

pub fn action_just_released(this: This, action: Actions) bool {
    std.debug.assert(action != .MAX_INPUT);

    return !this.frame[@intFromEnum(action)] and this.last_frame[@intFromEnum(action)];
}

inline fn float_from_bool(comptime T: type, v: bool) T {
    comptime std.debug.assert(T == f32 or T == f64 or T == f128 or T == comptime_float);
    return @as(T, @floatFromInt(@as(u1, @intFromBool(v))));
}

pub fn axis(this: This) @Vector(2, f32) {
    const right = float_from_bool(f32, this.action_pressed(.AxisRight));
    const left = float_from_bool(f32, this.action_pressed(.AxisLeft));
    const up = float_from_bool(f32, this.action_pressed(.AxisUp));
    const down = float_from_bool(f32, this.action_pressed(.AxisDown));

    const axisv: @Vector(2, f32) = .{ left - right, up - down };

    const len_squared: f32 = @reduce(.Add, axisv * axisv);
    if (len_squared <= std.math.floatEps(f32)) {
        return .{ 0.0, 0.0 };
    }

    const len: f32 = @sqrt(len_squared);

    return axisv / @as(@Vector(2, f32), @splat(len));
}

pub fn process_events(this: *This) void {
    @memcpy(&this.last_frame, &this.frame);

    if (this.mode == .Keyboard) {
        this.frame[@intFromEnum(Actions.TriggerLeft)] = false;
        this.frame[@intFromEnum(Actions.TriggerRight)] = false;

        this.mouse_x_previous = this.mouse_x;
        this.mouse_y_previous = this.mouse_y;

        _ = sdl.SDL_GetMouseState(&this.mouse_x, &this.mouse_y);
        _ = sdl.SDL_GetRelativeMouseState(&this.mouse_x_rel, &this.mouse_y_rel);
    }

    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        this.process_event(event);
    }
}

fn process_event(this: *This, event: sdl.SDL_Event) void {
    if (event.type == sdl.SDL_EVENT_QUIT) {
        this.close_condition = true;
        return;
    }

    switch (this.mode) {
        .Keyboard => this.process_event_mode_keyboard(event),
        .Controller => this.process_event_mode_controller(event),
    }
}

fn convert_scancode(scancode: c_uint) ?Actions {
    return switch (scancode) {
        sdl.SDL_SCANCODE_W => Actions.AxisUp,
        sdl.SDL_SCANCODE_S => Actions.AxisDown,
        sdl.SDL_SCANCODE_D => Actions.AxisRight,
        sdl.SDL_SCANCODE_A => Actions.AxisLeft,
        sdl.SDL_SCANCODE_SPACE => Actions.Jump,
        sdl.SDL_SCANCODE_E => Actions.Interact,
        sdl.SDL_SCANCODE_TAB => Actions.Inventory,
        sdl.SDL_SCANCODE_ESCAPE => Actions.Pause,
        sdl.SDL_SCANCODE_RSHIFT => Actions.Crouch,
        sdl.SDL_BUTTON_LEFT => Actions.Main,
        sdl.SDL_BUTTON_RIGHT => Actions.Secondary,
        sdl.SDL_BUTTON_MIDDLE => Actions.Terciary,
        else => null,
    };
}

fn process_event_mode_keyboard(this: *This, event: sdl.SDL_Event) void {
    switch (event.type) {
        sdl.SDL_EVENT_KEY_DOWN => {
            const input = convert_scancode(event.key.scancode) orelse return;
            this.frame[@intFromEnum(input)] = true;
        },
        sdl.SDL_EVENT_KEY_UP => {
            const input = convert_scancode(event.key.scancode) orelse return;
            this.frame[@intFromEnum(input)] = false;
        },
        sdl.SDL_EVENT_MOUSE_WHEEL => {
            const input = if (event.wheel.y > 0) Actions.TriggerLeft else Actions.TriggerRight;
            this.frame[@intFromEnum(input)] = true;
        },
        sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            const input = convert_scancode(event.button.button) orelse return;
            this.frame[@intFromEnum(input)] = true;
        },
        sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
            const input = convert_scancode(event.button.button) orelse return;
            this.frame[@intFromEnum(input)] = false;
        },
        else => {},
    }
}

fn process_event_mode_controller(this: *This, event: sdl.SDL_Event) void {
    std.debug.print("Controller mode not implemented\n", .{});
    _ = this;
    _ = event;
}

pub const Mode = enum {
    Keyboard,
    Controller,
};

pub const Actions = enum(usize) {
    AxisUp = 0,
    AxisDown,
    AxisRight,
    AxisLeft,
    Main,
    Secondary,
    Terciary,
    Interact,
    Jump,
    Inventory,
    Pause,
    TriggerLeft,
    TriggerRight,
    Crouch,
    MAX_INPUT,
};
