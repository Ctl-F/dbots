const std = @import("std");
const zalg = @import("zalgebra");

pub const vec2 = zalg.Vec2;
pub const vec3 = zalg.Vec3;
pub const vec4 = zalg.Vec4;
pub const mat4 = zalg.Mat4;
pub const quat = zalg.Quat;

pub inline fn deg_to_rad(degrees: f32) f32 {
    return zalg.toRadians(degrees);
}

pub inline fn rad_to_deg(radians: f32) f32 {
    return zalg.toDegrees(radians);
}

// const std = @import("std");

// pub const vec2 = @Vector(2, f32);
// pub const vec3 = @Vector(3, f32);
// pub const vec4 = @Vector(4, f32);

// // Vulkan Compatible Matrix:
// // 16 floats
// //
// // Order of composing transformations:
// // Model = Translation * Rotation * Scale;
// // const model = mat4_mul(translate, mat4_mul(rot, scale));
// //
// // mat[0..4] is the first COLUMN not ROW
// // Matrix Format
// // | 0  4  8 12 |
// // | 1  5  9 13 |
// // | 2  6 10 14 |
// // | 3  7 11 15 |
// pub const mat4 = [16]f32;

// const identity: mat4 = [16]f32{
//     1, 0, 0, 0,
//     0, 1, 0, 0,
//     0, 0, 1, 0,
//     0, 0, 0, 1,
// };

// pub inline fn dot(vec_a: anytype, vec_b: anytype) f32 {
//     switch (@TypeOf(vec_a)) {
//         vec2, vec3, vec4 => {},
//         else => @compileError("Expected vector type for dot product. Got: " ++ @typeName(@TypeOf(vec_a))),
//     }
//     if (@TypeOf(vec_a) != @TypeOf(vec_b)) {
//         @compileError("Both sides of the dot product must be the same type!");
//     }

//     return @as(f32, @reduce(.Add, vec_a * vec_b));
// }

// pub inline fn cross(a: vec3, b: vec3) vec3 {
//     return vec3{
//         a[1] * b[2] - a[2] * b[1],
//         a[2] * b[0] - a[0] * b[2],
//         a[0] * b[1] - a[1] * b[0],
//     };
// }

// pub inline fn length(a: anytype) f32 {
//     switch (@TypeOf(a)) {
//         vec2, vec3, vec4 => {},
//         else => @compileError("Invalid type for normalized. Expected vector type got: " ++ @typeName(@TypeOf(a))),
//     }

//     return @sqrt(dot(a, a));
// }

// pub inline fn normalized(a: anytype) @TypeOf(a) {
//     switch (@TypeOf(a)) {
//         vec2, vec3, vec4 => {},
//         else => @compileError("Invalid type for normalized. Expected vector type got: " ++ @typeName(@TypeOf(a))),
//     }

//     return a / @as(@TypeOf(a), @splat(length(a)));
// }

// pub inline fn mat4_build_ident() mat4 {
//     return identity;
// }

// pub inline fn mat4_row(mat: mat4, row: usize) vec4 {
//     const width = 4;
//     std.debug.assert(row < width);
//     return vec4{
//         mat[row + (width * 0)],
//         mat[row + (width * 1)],
//         mat[row + (width * 2)],
//         mat[row + (width * 3)],
//     };
// }

// pub inline fn mat4_transpose(mat: mat4) mat4 {
//     const load: @Vector(16, f32) = mat;
//     const mask = @Vector(16, f32){
//         0, 4, 8,  12,
//         1, 5, 9,  13,
//         2, 6, 10, 14,
//         3, 7, 11, 15,
//     };
//     const result = @shuffle(f32, load, undefined, mask);
//     return result;
// }

// pub fn mat4_build_translation(position: vec3) mat4 {
//     var translation = mat4_build_ident();
//     translation[12] = position[0];
//     translation[13] = position[1];
//     translation[14] = position[2];
//     return translation;
// }

// pub fn mat4_build_scale(scale: vec3) mat4 {
//     var scalemat = mat4_build_ident();
//     scalemat[0] = scale[0];
//     scalemat[5] = scale[1];
//     scalemat[10] = scale[2];
//     return scalemat;
// }

// pub fn mat4_build_rotation_x(angle: f32) mat4 {
//     const cos = @cos(angle);
//     const sin = @sin(angle);

//     var mat = mat4_build_ident();

//     mat[5] = cos;
//     mat[6] = -sin;
//     mat[9] = sin;
//     mat[10] = cos;

//     return mat;
// }

// pub fn mat4_build_rotation_y(angle: f32) mat4 {
//     const cos = @cos(angle);
//     const sin = @sin(angle);

//     var mat = mat4_build_ident();

//     mat[0] = cos;
//     mat[2] = sin;
//     mat[8] = -sin;
//     mat[10] = cos;

//     return mat;
// }

// pub fn mat4_build_rotation_z(angle: f32) mat4 {
//     const cos = @cos(angle);
//     const sin = @sin(angle);

//     var mat = mat4_build_ident();

//     mat[0] = cos;
//     mat[1] = -sin;
//     mat[4] = sin;
//     mat[5] = cos;

//     return mat;
// }

// pub fn mat4_build_perspective(fov: f32, aspect: f32, znear: f32, zfar: f32) mat4 {
//     var mat = std.mem.zeroes(mat4);

//     std.debug.assert(znear - zfar != 0);

//     const f = 1.0 / @tan(fov / 2);
//     const k = zfar / (zfar - znear);

//     mat[0] = f / aspect;
//     mat[5] = f;
//     mat[10] = k;
//     mat[11] = 1;
//     mat[14] = -znear * k;

//     // mat[0] = f / aspect;
//     // mat[5] = f;
//     // mat[10] = zfar / (znear - zfar); // (zfar + znear) / (znear - zfar);
//     // mat[11] = -1;
//     // mat[14] = zfar * znear / (znear - zfar);

//     return mat;
// }

// pub fn mat4_build_lookat(eye: vec3, center: vec3, up: vec3) mat4 {
//     var mat = std.mem.zeroes(mat4);

//     const forward = normalized(center - eye);
//     const right = normalized(cross(forward, up));
//     const new_up = normalized(cross(right, forward));

//     // mat[0] = right[0];
//     // mat[1] = new_up[0];
//     // mat[2] = -forward[0];
//     // mat[4] = right[1];
//     // mat[5] = new_up[1];
//     // mat[6] = -forward[1];
//     // mat[8] = right[2];
//     // mat[9] = new_up[2];
//     // mat[10] = -forward[2];
//     // mat[12] = -dot(right, eye);
//     // mat[12] = -dot(up, eye);
//     // mat[14] = dot(forward, eye);
//     // mat[15] = 1;

//     mat[0] = right[0];
//     mat[1] = right[1];
//     mat[2] = right[2];
//     mat[3] = -dot(right, eye);

//     mat[4] = new_up[0];
//     mat[5] = new_up[1];
//     mat[6] = new_up[2];
//     mat[7] = -dot(new_up, eye);

//     mat[8] = -forward[0];
//     mat[9] = -forward[1];
//     mat[10] = -forward[2];
//     mat[11] = dot(forward, eye);

//     mat[15] = 1;

//     return mat;
// }

// pub fn mat4_build_rotation(angles: vec3) mat4 {
//     const rot_z = if (angles[2] != 0.0) mat4_build_rotation_z(angles[2]) else mat4_build_ident();
//     const rot_y = if (angles[1] != 0.0) mat4_build_rotation_y(angles[1]) else mat4_build_ident();
//     const rot_x = if (angles[0] != 0.0) mat4_build_rotation_x(angles[0]) else mat4_build_ident();

//     return mat4_mul(rot_z, mat4_mul(rot_y, rot_x));
// }

// inline fn mat4_mul_vec4(mat: mat4, vec: vec4) vec4 {
//     const result: vec4 =
//         @as(vec4, @splat(vec[0])) * @as(vec4, mat[0..4].*) +
//         @as(vec4, @splat(vec[1])) * @as(vec4, mat[4..8].*) +
//         @as(vec4, @splat(vec[2])) * @as(vec4, mat[8..12].*) +
//         @as(vec4, @splat(vec[3])) * @as(vec4, mat[12..16].*);

//     return result;
// }

// inline fn mat4_mul_mat4(a: mat4, b: mat4) mat4 {
//     var result: mat4 = undefined;

//     inline for (0..4) |idx| {
//         const start = idx * 4;
//         const end = start + 4;

//         const column = mat4_mul_vec4(a, b[start..end].*);
//         var buffer: [4]f32 = undefined;
//         const slice = buffer[0..];
//         slice.* = column;
//         @memcpy(result[start..end], slice);
//     }

//     return result;
// }

// pub fn mat4_mul(a: mat4, b: anytype) @TypeOf(b) {
//     switch (@TypeOf(b)) {
//         vec4 => return mat4_mul_vec4(a, b),
//         mat4 => return mat4_mul_mat4(a, b),
//         else => @compileError("Invalid type for mat4_mul. Expected mat4 or vec4, Got: " ++ @typeName(@TypeOf(b))),
//     }
// }

// pub fn print_mat(mat: mat4) void {
//     const c = mat4_transpose(mat);

//     inline for (0..4) |idx| {
//         std.debug.print("| {d: >3} {d: >3} {d: >3} {d: >3} |\n", .{ c[idx * 4], c[idx * 4 + 1], c[idx * 4 + 2], c[idx * 4 + 3] });
//     }
// }
