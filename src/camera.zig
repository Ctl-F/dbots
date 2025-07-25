const std = @import("std");
const math = @import("math.zig");

pub const PerspectiveCamera = struct {
    const This = @This();

    projection: math.mat4,
    position: math.vec3,
    angle: math.quat,
    up: math.vec3,
    pitch: f32,
    pitch_min: f32 = math.rad_to_deg(-@as(f32, @floatCast(std.math.pi)) / 2 + 0.01),
    pitch_max: f32 = math.rad_to_deg(@as(f32, @floatCast(std.math.pi)) / 2 - 0.01),

    pub fn init(fov: f32, aspect: f32, near: f32, up: math.vec3) This {
        return .{
            .projection = math.mat4.perspectiveReversedZ(fov, aspect, near),
            .position = math.vec3.zero(),
            .angle = math.quat.identity(),
            .up = up,
            .pitch = 0,
        };
    }

    pub inline fn forward(this: This) math.vec3 {
        return this.angle.rotateVec(math.vec3.forward());
    }

    pub fn get_view(this: This) math.mat4 {
        return math.mat4.lookAt(this.position, this.position.add(this.forward()), this.up);
    }
};
