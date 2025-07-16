import bpy
import bmesh
import struct
import mathutils, math

# ExportHelper is a helper class, defines filename and
# invoke() function which calls the file selector.
from bpy_extras.io_utils import ExportHelper
from bpy.props import StringProperty, BoolProperty, EnumProperty
from bpy.types import Operator


def write_some_data(context, filepath, explicit_triangulate, y_up):
    what = context.active_object;

    if what == None:
        return {"SELECT OBJECT FOR EXPORT"}

    mesh = what.data.copy();

    #mesh.calc_loop_triangles()
    #mesh.calc_normals()


    if explicit_triangulate:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm, faces=bm.faces)

        bm.calc_loop_triangles()
        bm.normal_update()

        bm.to_mesh(mesh)
        bm.free()

    uv_layer = mesh.uv_layers.active.data if mesh.uv_layers.active else None

    rotation = mathutils.Matrix.Rotation(-math.pi/2, 4, 'X') if y_up else mathutils.Matrix.Identity(4)

    with open(filepath, "wb") as f:
        write_header(f, len(mesh.loop_triangles) * 3)

        for tri in mesh.loop_triangles:
            polygon = mesh.polygons[tri.polygon_index]

            for loop_index in tri.loops:
                vertex_index = mesh.loops[loop_index].vertex_index;
                vertex = mesh.vertices[vertex_index];
                pos = rotation @ vertex.co;
                uv = uv_layer[loop_index].uv if uv_layer else (0.0, 0.0)

                normal = None
                if polygon.use_smooth:
                    normal = rotation.to_3x3() @ mesh.loops[loop_index].normal
                else:
                    normal = rotation.to_3x3() @ polygon.normal


                # output vertex in x,y,z,normalx,normaly,normalz,u,v,r,g,b format
                f.write(struct.pack('fffffffffff', float(pos[0]), float(pos[1]), float(pos[2]), float(normal[0]), float(normal[1]), float(normal[2]), float(uv[0]), float(uv[1]), float(1), float(1), float(1)))


    bpy.data.meshes.remove(mesh)

    return {'FINISHED'}

"""
    ATTRIB_ENUM:
        00000001 Position2
        00000010 Normal2
        00000011 Uv2
        00000100 Color3
        00010001 Position3
        00010010 Normal3
        00010011 Uv4
        00010100 Color4
"""

def write_header(f, vertex_count):
    f.write(b"RVB1")
    f.write(struct.pack('I', 1)) #version
    f.write(struct.pack('I', int(vertex_count)))
    f.write(struct.pack('I', 4)) #attrib count
    f.write(struct.pack('IIII', int(0b00010001), int(0b00010010), int(0b00000011), int(0b00000100))) #attribs



class ExportSomeData(Operator, ExportHelper):
    """This appears in the tooltip of the operator and in the generated docs"""
    bl_idname = "export_test.some_data"  # important since its how bpy.ops.import_test.some_data is constructed
    bl_label = "Raw Vertex Buffer"

    # ExportHelper mix-in class uses this.
    filename_ext = ".rvb"

    filter_glob: StringProperty(
        default="*.rvb",
        options={'HIDDEN'},
        maxlen=255,  # Max internal buffer length, longer would be clamped.
    )

    # List of operator properties, the attributes will be assigned
    # to the class instance from the operator settings before calling.
    explicit_triangulate: BoolProperty(
        name="Triangulate",
        description="Perform Triangulation Operation prior to export",
        default=True,
    )

    y_up: BoolProperty(
        name="Y-Up",
        description="Swap y/z axis so y is up",
        default=True,
    )


    def execute(self, context):
        return write_some_data(context, self.filepath, self.explicit_triangulate, self.y_up)


# Only needed if you want to add into a dynamic menu
def menu_func_export(self, context):
    self.layout.operator(ExportSomeData.bl_idname, text="Raw Vertex Buffer")


# Register and add to the "file selector" menu (required to use F3 search "Text Export Operator" for quick access).
def register():
    bpy.utils.register_class(ExportSomeData)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.utils.unregister_class(ExportSomeData)
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)


if __name__ == "__main__":
    register()

    # test call
    bpy.ops.export_test.some_data('INVOKE_DEFAULT')
