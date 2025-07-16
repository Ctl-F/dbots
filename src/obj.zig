const std = @import("std");
const host = @import("host.zig");
const assets = @import("assets.zig");
//const tinyobj = @cImport(@cInclude("tinyobj_loader_c.h"));

pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    color: [3]f32,

    pub fn fmt(format: *host.VertexFormat) void {
        format.clear();
        format.add(.Float3) catch unreachable; // the only error possible is TOO_MANY_ELEMENTS
        format.add(.Float3) catch unreachable; // and we literally only have 3 and have JUST
        format.add(.Float2) catch unreachable; // created the format. I think we can ignore the error
        format.add(.Float3) catch unreachable;
    }
};

const Header = extern struct {
    magic_number: [4]u8,
    version: u32,
    vertex_count: u32,
    attrib_count: u32,
};

const MAGIC_NUMBER = "RVB1";
const VERSION = 1;
const EXPECTED_ATTRIBS = [_]u32{
    0b00010001, // position3
    0b00010010, // normal3
    0b00000011, // uv2
    0b00000100, // color 3
};

pub fn load_mesh(allocator: std.mem.Allocator, data: []align(@alignOf(u32)) const u8) ![]Vertex {
    const header: *const Header = std.mem.bytesAsValue(Header, data[0..@sizeOf(Header)]);
    try assert_version_and_magic(header);

    const vertices = try allocator.alloc(Vertex, header.vertex_count);
    errdefer allocator.free(vertices);

    if (header.attrib_count > 64) {
        std.debug.print("Massive attribute count detected. Possible endianness mismatch. Data will not be loaded.\n", .{});
        return error.TooManyAttribs;
    }

    const expected_size = @sizeOf(Header) + @sizeOf(u32) * header.attrib_count + @sizeOf(Vertex) * header.vertex_count;
    if (data.len < expected_size) { // we can allow for larger because we allow padding at the end, but never smaller
        return error.ExpectedSizeMismatch;
    }

    const attribs: [*]const u32 = @ptrCast(@alignCast(data.ptr + @sizeOf(Header)));
    if (header.attrib_count != EXPECTED_ATTRIBS.len) {
        return error.FormatMismatch;
    }
    for (0..header.attrib_count) |idx| {
        if (attribs[idx] != EXPECTED_ATTRIBS[idx]) {
            return error.FormatMismatch;
        }
    }

    const floats: [*]const f32 = @ptrCast(@alignCast(data.ptr + @sizeOf(Header) + @sizeOf(u32) * header.attrib_count));
    const packed_floats: [*]const Vertex = @ptrCast(floats);
    @memcpy(vertices, packed_floats[0..vertices.len]);

    return vertices;
}

fn assert_version_and_magic(header: *const Header) !void {
    if (!std.mem.eql(u8, MAGIC_NUMBER, &header.magic_number)) {
        return error.MagicMismatch;
    }
    if (header.version > VERSION) {
        return error.VersionMismatch;
    }
}

// const Handle = extern struct {
//     allocator: std.mem.Allocator,
//     handle: ?[]u8,
// };

// //pub const file_reader_callback = ?*const fn (?*anyopaque, [*c]const u8, c_int, [*c]const u8, [*c][*c]u8, [*c]usize) callconv(.c) void;
// pub export fn _file_reader_callback(
//     ctx: ?*anyopaque,
//     filename: [*c]const u8,
//     is_mtl: c_int,
//     obj_filename: [*c]const u8,
//     data: [*c][*c]u8,
//     size: [*c]usize,
// ) callconv(.c) void {
//     _ = is_mtl;
//     _ = obj_filename;

//     const handle: ?*Handle = @ptrCast(@alignCast(ctx));

//     if (handle == null or filename == null) {
//         std.debug.print("NULL Handle\n", .{});
//         data = null;
//         size = null;
//         return;
//     }

//     handle.?.handle = assets.read_file_resolvedz(handle.?.allocator, filename[0..std.mem.len(filename)]);
// }

// pub fn parse_obj(allocator: std.mem.Allocator, filename: [:0]const u8) ![]Vertex {
//     var attrib: tinyobj.tinyobj_attrib_t = undefined;
//     var shapes: ?[*c]tinyobj.tinyobj_shape_t = null;
//     var num_shapes: usize = 0;
//     var materials: ?[*c]tinyobj.tinyobj_material_t = null;
//     var num_materials: usize = 0;

//     var handle: Handle = .{
//         .allocator = allocator,
//         .handle = null,
//     };
//     defer {
//         if (handle.handle) |ptr| {
//             handle.allocator.free(ptr);
//         }
//     }

//     const result = tinyobj.tinyobj_parse_obj(
//         &attrib,
//         &shapes,
//         &num_shapes,
//         &materials,
//         &num_materials,
//         filename.ptr,
//         _file_reader_callback,
//         &handle,
//         tinyobj.TINYOBJ_FLAG_TRIANGULATE,
//     );
//     if (result != tinyobj.TINYOBJ_SUCCESS) {
//         return error.ParserError;
//     }

//     var vertices = std.ArrayList(Vertex).init(allocator);
//     defer vertices.deinit();

//     for(0..@as(usize, @intCast(attrib.)))
// }
