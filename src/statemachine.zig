const std = @import("std");

// State type must define:
// pub fn construct(ctx: *SharedState) !@This() {}
// pub fn destroy(this: @This()) void {};
// pub fn on_enter(this: *This(), from: ?*StateInfo, ctx: *SharedState) !void {}
// pub fn step(this: *This(), ctx: *SharedState) !?States {}
// pub fn on_exit(this: *This(), to: ?*StateInfo, ctx: *SharedState) !void {}
// data that needs to persist outside of the state instance should be part of the shared state
// each transition will bring a new state

pub fn StateMachine(comptime SharedCtx: type, comptime StateID: type, comptime NullState: StateID) type {
    return struct {
        const This = @This();

        pub const State = struct {
            const Self = @This();
            id: StateID,
            context: *anyopaque,
            vtable: VTable,

            pub const VTable = struct {
                on_enter: *const fn (ctx: *anyopaque, shared: *SharedCtx, from: ?*State) anyerror!void,
                on_exit: *const fn (ctx: *anyopaque, shared: *SharedCtx, to: ?*State) anyerror!void,
                on_step: *const fn (ctx: *anyopaque, shared: *SharedCtx, dt: f32) anyerror!StateID,
            };

            pub inline fn enter(this: Self, ctx: *SharedCtx, from: ?*State) anyerror!void {
                return try this.vtable.on_enter(this.context, ctx, from);
            }
            pub inline fn exit(this: Self, ctx: *SharedCtx, to: ?*State) anyerror!void {
                return try this.vtable.on_exit(this.context, ctx, to);
            }
            pub inline fn step(this: Self, ctx: *SharedCtx, dt: f32) anyerror!StateID {
                return try this.vtable.on_step(this.context, ctx, dt);
            }
        };

        states: std.AutoHashMap(StateID, State),
        current_state: StateID,
        context: *SharedCtx,

        pub fn init(allocator: std.mem.Allocator, contextPtr: *SharedCtx) This {
            return This{
                .states = std.AutoHashMap(StateID, State).init(allocator),
                .current_state = NullState,
                .context = contextPtr,
            };
        }

        pub fn deinit(this: *This) void {
            if (this.current_state != NullState) {
                if (this.states.getPtr(this.current_state)) |handle| {
                    handle.exit(this.context, null) catch unreachable;
                } else {
                    unreachable;
                }
            }

            this.states.deinit();
        }

        pub fn add_state(this: *This, state: State) !void {
            try this.states.put(state.id, state);
        }

        pub fn begin(this: *This, state: StateID) !void {
            if (this.states.getPtr(state)) |handle| {
                this.current_state = state;
                try handle.enter(this.context, null);
            } else {
                unreachable;
            }
        }

        pub fn step(this: *This, dt: f32) !void {
            if (this.states.getPtr(this.current_state)) |current| {
                const new_state = try current.step(this.context, dt);

                if (new_state == NullState) {
                    return;
                }

                if (this.states.getPtr(new_state)) |next| {
                    try current.exit(this.context, next);
                    try next.enter(this.context, current);
                    this.current_state = new_state;
                } else {
                    unreachable;
                }
            } else {
                unreachable;
            }
        }
    };
}

// StateMachine(stateType, contextType)
// provides an interface to create a state-machine based off of a union type.
// The union types are expected to follow a basic union interface
//
// const SharedState = struct {};
//
// const States = enum { Running, Paused };
//
// const StateInfo = union(States) {
//     const StatesType = @This();
//
//     Running: RunningState,
//     Paused: PausedState,
//
//     pub const RunningState = struct {
//         pub fn construct(ctx: *SharedState) !@This() {}
//         pub fn destroy(this: @This()) void {};
//         pub fn on_enter(this: *This(), from: ?*StateInfo, ctx: *SharedState) !void {}
//         pub fn step(this: *This(), ctx: *SharedState) !?States {}
//         pub fn on_exit(this: *This(), to: ?*StateInfo, ctx: *SharedState) !void {}
//     };
//
//     pub const PausedState = struct {
//         pub fn construct(ctx: *SharedState) !@This() {}
//         pub fn destroy(this: @This()) void {};
//         pub fn on_enter(this: *This(), from: ?*StateInfo, ctx: *SharedState) !void {}
//         pub fn step(this: *This(), ctx: *SharedState) !?States {}
//         pub fn on_exit(this: *This(), to: ?*StateInfo, ctx: *SharedState) !void {}
//     };
// };
//
// const AppMachine = StateMachine(StateInfo, SharedState);
// const appMachine = try AppMachine.init(States.Running, SharedState{});
// ...
// pub fn StateMachine(comptime stateUnion: type, comptime contextType: type) type {
//     const typeInfo = @typeInfo(stateUnion);
//     if (typeInfo != std.builtin.Type.@"union") {
//         @compileError("StateMachine expects a tagged-union union(enum) parameter.");
//     }

//     const unionInfo = typeInfo.@"union";

//     if (unionInfo.tag_type == null) {
//         @compileError("StateMachine parameter is a union, but is not a tagged union. union(enum) expected.");
//     }

//     return struct {
//         pub const This = @This();
//         pub const StateType = unionInfo.tag_type.?;
//         pub const State = stateUnion;
//         pub const ContextType = contextType;

//         state: stateUnion,

//         pub fn init(initialState: This.StateType, context: *This.ContextType) !This {
//             const initState = try construct(initialState, context);
//             try initState.on_enter(null, context);
//             return This{
//                 .state = initState,
//             };
//         }

//         pub fn deinit(this: This, context: *This.ContextType) void {
//             this.state.on_exit(null, context) catch {};
//             this.state.destroy(context);
//         }

//         pub fn step(this: *This, context: *This.ContextType) !void {
//             const transitionState = try this.state.step(context);

//             if (transitionState) |state| {
//                 const nextState = try construct(state, context);

//                 try this.state.on_exit(&nextState, context);
//                 try nextState.on_enter(&this.state, context);

//                 this.state.destruct(context);
//                 this.state = nextState;
//             }
//         }

//         fn construct(stateType: This.StateType, context: *This.ContextType) !This.State {
//             return switch (stateType) {
//                 inline else => |t| {
//                     const field = @field(This.State, @tagName(t));
//                     if (!@hasDecl(@TypeOf(field), "construct")) {
//                         @compileError("Each state must define a construct() method. " ++ @typeName(@TypeOf(field)) ++ " does not in " ++ @typeName(This.StateType) ++ " and " ++ @typeName(This.State));
//                     } //TODO: Fix state machine
//                     return try field.construct(context);
//                 },
//             };
//         }
//     };
// }
