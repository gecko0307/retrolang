bl_info = {
    "name": "PlayStation Boot Logo TMD",
    "author": "Retrolang",
    "version": (1, 0, 0),
    "blender": (4, 5, 0),
    "location": "File > Export > PlayStation Boot Logo (.tmd)",
    "description": "Export a simple, centered TMD for the PlayStation boot logo",
    "category": "Import-Export",
}

import struct

import bpy
from bpy.props import StringProperty
from bpy_extras.io_utils import ExportHelper

TMD_ID = 0x41
NORMAL_ONE = 4096
LOGO_MAX_BYTES = 14336
LOGO_MAX_EXTENT = 1000.0


class TMDExportError(Exception):
    pass


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _normalize(v):
    length = sum(c * c for c in v) ** 0.5
    if length == 0.0:
        return None
    return tuple(c / length for c in v)


def _rgb8(color):
    return tuple(max(0, min(255, int(round(float(color[i]) * 255.0)))) for i in range(3))


def _material_color(mesh, material_index):
    if 0 <= material_index < len(mesh.materials):
        material = mesh.materials[material_index]
        if material is not None:
            return _rgb8(material.diffuse_color)
    return (192, 192, 192)


def _collect_triangles(context):
    depsgraph = context.evaluated_depsgraph_get()
    triangles = []

    for obj in context.view_layer.objects:
        if obj.type != 'MESH' or not obj.visible_get():
            continue

        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            for triangle in mesh.loop_triangles:
                points = []
                for vertex_index in triangle.vertices:
                    world = evaluated.matrix_world @ mesh.vertices[vertex_index].co
                    points.append((float(world.x), float(world.y), float(world.z)))
                triangles.append((points, _material_color(mesh, triangle.material_index)))
        finally:
            evaluated.to_mesh_clear()

    if not triangles:
        raise TMDExportError("No visible mesh triangles to export")
    return triangles


def _make_tmd(triangles):
    points = [point for triangle, _ in triangles for point in triangle]
    mins = tuple(min(p[i] for p in points) for i in range(3))
    maxs = tuple(max(p[i] for p in points) for i in range(3))
    center = tuple((mins[i] + maxs[i]) * 0.5 for i in range(3))
    extent = max(maxs[i] - mins[i] for i in range(3))
    if extent <= 0.0:
        raise TMDExportError("The exported model has zero size")
    scale = LOGO_MAX_EXTENT / extent

    vertex_map = {}
    vertices = []
    normal_map = {}
    normals = []
    primitives = bytearray()
    primitive_count = 0

    def vertex_index(point):
        x, y, z = point
        key = (
            int(round((x - center[0]) * scale)),
            int(round(-(z - center[2]) * scale)),
            int(round((y - center[1]) * scale)),
        )
        index = vertex_map.get(key)
        if index is None:
            index = len(vertices)
            if index > 0xFFFF:
                raise TMDExportError("Model exceeds the TMD 16-bit vertex-index limit")
            vertex_map[key] = index
            vertices.append(key)
        return index

    def normal_index(normal):
        key = tuple(int(round(c * NORMAL_ONE)) for c in normal)
        index = normal_map.get(key)
        if index is None:
            index = len(normals)
            if index > 0xFFFF:
                raise TMDExportError("Model exceeds the TMD 16-bit normal-index limit")
            normal_map[key] = index
            normals.append(key)
        return index

    for points, color in triangles:
        converted = [(p[0], -p[2], p[1]) for p in points]
        edge1 = tuple(converted[1][i] - converted[0][i] for i in range(3))
        edge2 = tuple(converted[2][i] - converted[0][i] for i in range(3))
        face_normal = _normalize(_cross(edge1, edge2))
        if face_normal is None:
            continue

        # Match the vertex winding convention used by the existing BIOS logo TMDs.
        ordered = (points[0], points[2], points[1])
        indices = tuple(vertex_index(p) for p in ordered)
        n_index = normal_index(face_normal)
        primitives.extend(struct.pack(
            "<4B4B4H",
            4, 3, 0, 0x20,
            color[0], color[1], color[2], 0x20,
            n_index, indices[0], indices[1], indices[2],
        ))
        primitive_count += 1

    if primitive_count == 0:
        raise TMDExportError("The model contains no non-degenerate triangles")

    vertex_data = b"".join(struct.pack("<4h", *v, 0) for v in vertices)
    normal_data = b"".join(struct.pack("<4h", *n, 0) for n in normals)
    object_table_size = 28
    primitive_top = object_table_size
    vertex_top = primitive_top + len(primitives)
    normal_top = vertex_top + len(vertex_data)
    object_record = struct.pack(
        "<6Ii",
        vertex_top, len(vertices),
        normal_top, len(normals),
        primitive_top, primitive_count,
        0,
    )
    result = (
        struct.pack("<3I", TMD_ID, 0, 1)
        + object_record
        + bytes(primitives)
        + vertex_data
        + normal_data
    )

    if len(result) > LOGO_MAX_BYTES:
        raise TMDExportError(
            f"TMD is {len(result)} bytes; only {LOGO_MAX_BYTES} bytes fit in the boot logo area"
        )
    return result


class EXPORT_SCENE_OT_boot_logo_tmd(bpy.types.Operator, ExportHelper):
    """Export visible meshes as a simple PlayStation boot-logo TMD"""
    bl_idname = "export_scene.boot_logo_tmd"
    bl_label = "Export PlayStation Boot Logo"
    bl_options = {'PRESET'}

    filename_ext = ".tmd"
    filter_glob: StringProperty(default="*.tmd", options={'HIDDEN'})

    def execute(self, context):
        try:
            data = _make_tmd(_collect_triangles(context))
            with open(self.filepath, "wb") as output:
                output.write(data)
        except (OSError, TMDExportError) as error:
            self.report({'ERROR'}, str(error))
            return {'CANCELLED'}

        self.report({'INFO'}, f"Exported boot logo TMD ({len(data)} bytes)")
        return {'FINISHED'}


def menu_func_export(self, context):
    self.layout.operator(
        EXPORT_SCENE_OT_boot_logo_tmd.bl_idname,
        text="PlayStation Boot Logo (.tmd)",
    )


def register():
    bpy.utils.register_class(EXPORT_SCENE_OT_boot_logo_tmd)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)
    bpy.utils.unregister_class(EXPORT_SCENE_OT_boot_logo_tmd)


if __name__ == "__main__":
    register()
