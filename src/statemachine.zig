const std = @import("std");

/// StateMachine(stateType, contextType)
/// provides an interface to create a state-machine based off of a union type.
/// The union types are expected to follow a basic union interface
///
/// const SharedState = struct {};
///
/// const States = enum { Running, Paused };
///
/// const StateInfo = union(States) {
///     const StatesType = @This();
///
///     Running: RunningState,
///     Paused: PausedState,
///
///     pub const RunningState = struct {
///         pub fn construct(ctx: *SharedState) !@This() {}
///         pub fn destroy(this: @This()) void {};
///         pub fn on_enter(this: *This(), from: ?*StateInfo, ctx: *SharedState) !void {}
///         pub fn step(this: *This(), ctx: *SharedState) !?States {}
///         pub fn on_exit(this: *This(), to: ?*StateInfo, ctx: *SharedState) !void {}
///     };
///
///     pub const PausedState = struct {
///         pub fn construct(ctx: *SharedState) !@This() {}
///         pub fn destroy(this: @This()) void {};
///         pub fn on_enter(this: *This(), from: ?*StateInfo, ctx: *SharedState) !void {}
///         pub fn step(this: *This(), ctx: *SharedState) !?States {}
///         pub fn on_exit(this: *This(), to: ?*StateInfo, ctx: *SharedState) !void {}
///     };
/// };
///
/// const AppMachine = StateMachine(StateInfo, SharedState);
/// const appMachine = try AppMachine.init(States.Running, SharedState{});
/// ...
pub fn StateMachine(comptime stateUnion: type, comptime contextType: type) type {
    const typeInfo = @typeInfo(stateUnion);
    if (typeInfo != std.builtin.Type.@"union") {
        @compileError("StateMachine expects a tagged-union union(enum) parameter.");
    }

    const unionInfo = typeInfo.@"union";

    if (unionInfo.tag_type == null) {
        @compileError("StateMachine parameter is a union, but is not a tagged union. union(enum) expected.");
    }

    return struct {
        pub const This = @This();
        pub const StateType = unionInfo.tag_type.?;
        pub const State = stateUnion;
        pub const ContextType = contextType;

        state: stateUnion,

        pub fn init(initialState: This.StateType, context: *This.ContextType) !This {
            const initState = try construct(initialState, context);
            try initState.on_enter(null, context);
            return This{
                .state = initState,
            };
        }

        pub fn deinit(this: This, context: *This.ContextType) void {
            this.state.on_exit(null, context) catch {};
            this.state.destroy(context);
        }

        pub fn step(this: *This, context: *This.ContextType) !void {
            const transitionState = try this.state.step(context);

            if (transitionState) |state| {
                const nextState = try construct(state, context);

                try this.state.on_exit(&nextState, context);
                try nextState.on_enter(&this.state, context);

                this.state.destruct(context);
                this.state = nextState;
            }
        }

        fn construct(stateType: This.StateType, context: *This.ContextType) !This.State {
            return switch (stateType) {
                inline else => |t| {
                    const field = @field(This.State, @tagName(t));
                    if (!@hasDecl(@TypeOf(field), "construct")) {
                        @compileError("Each state must define a construct() method. " ++ @typeName(@TypeOf(field)) ++ " does not in " ++ @typeName(This.StateType) ++ " and " ++ @typeName(This.State));
                    } //TODO: Fix state machine
                    return try field.construct(context);
                },
            };
        }
    };
}
