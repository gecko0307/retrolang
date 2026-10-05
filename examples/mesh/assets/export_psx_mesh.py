bl_info = {
    "name": "PSX mesh export (.psm)",
    "author": "-",
    "version": (1, 0, 0),
    "blender": (2, 80, 0),
    "location": "File > Export > PSX mesh (.psm)",
    "description": "Exports the active mesh as a compact binary for PS1 homebrew",
    "category": "Import-Export",
}

import struct

import bpy
from bpy.props import BoolProperty, FloatProperty, IntProperty
from bpy_extras.io_utils import ExportHelper

# ---------------------------------------------------------------------------
# File layout (little endian)
#
#   offset 0   header, 16 bytes
#       ushort numVerts
#       ushort numTris
#       ushort texW         texture width in pixels used for the UV conversion
#       ushort texH
#       uint   uvOffset     from start of file
#       uint   idxOffset    from start of file
#   offset 16  vertices, numVerts * 8 bytes: short x, y, z, pad   (GTE input format)
#   uvOffset   UVs,      numVerts * 2 bytes: uchar u, v           (padded to 4 bytes)
#   idxOffset  indices,  numTris * 3 * 2 bytes: ushort            (padded to 4 bytes)
#
# One output vertex per unique (position, UV) pair, so the same index addresses
# both the position array and the UV array.
# ---------------------------------------------------------------------------

HEADER_SIZE = 16


def pad4(n):
    return (n + 3) & ~3


def pack_mesh(verts, uvs, indices, tex_w, tex_h):
    """verts: [(x, y, z)] ints, uvs: [(u, v)] ints, indices: flat list of ints."""
    n = len(verts)
    t = len(indices) // 3
    if n > 65535:
        raise ValueError("too many vertices after splitting: %d (max 65535)" % n)

    uv_off = HEADER_SIZE + n * 8
    idx_off = uv_off + pad4(n * 2)

    out = bytearray()
    out += struct.pack("<HHHHII", n, t, tex_w, tex_h, uv_off, idx_off)
    for x, y, z in verts:
        out += struct.pack("<hhhh", x, y, z, 0)
    for u, v in uvs:
        out += struct.pack("<BB", u, v)
    out += b"\0" * (pad4(n * 2) - n * 2)
    for i in indices:
        out += struct.pack("<H", i)
    out += b"\0" * (pad4(len(indices) * 2) - len(indices) * 2)
    return bytes(out)


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def build_mesh(obj, depsgraph, scale, tex_w, tex_h, flip_v, flip_winding, apply_transform):
    eval_obj = obj.evaluated_get(depsgraph)  # modifiers applied
    mesh = eval_obj.to_mesh()
    warnings = {"uv_range": 0, "coord_range": 0}
    try:
        mesh.calc_loop_triangles()
        uv_layer = mesh.uv_layers.active
        if uv_layer is None:
            raise ValueError("mesh '%s' has no UV map" % obj.name)
        uv_data = uv_layer.data

        matrix = eval_obj.matrix_world if apply_transform else None

        verts, uvs, indices = [], [], []
        lookup = {}

        for tri in mesh.loop_triangles:
            corner = []
            for vi, li in zip(tri.vertices, tri.loops):
                co = mesh.vertices[vi].co
                if matrix is not None:
                    co = matrix @ co

                # Blender: X right, Y forward, Z up
                # PS1:     X right, Y down,    Z into the screen
                px, py, pz = co.x, -co.z, co.y
                ip = []
                for c in (px, py, pz):
                    c = int(round(c * scale))
                    if c < -32768 or c > 32767:
                        warnings["coord_range"] += 1
                        c = clamp(c, -32768, 32767)
                    ip.append(c)

                u, v = uv_data[li].uv
                if flip_v:
                    v = 1.0 - v  # Blender V starts at the bottom, TIM rows at the top
                if u < -0.001 or u > 1.001 or v < -0.001 or v > 1.001:
                    warnings["uv_range"] += 1
                # u = 1.0 maps to the last texel, not one past it
                iu = clamp(int(round(u * tex_w)), 0, tex_w - 1)
                iv = clamp(int(round(v * tex_h)), 0, tex_h - 1)

                key = (ip[0], ip[1], ip[2], iu, iv)
                idx = lookup.get(key)
                if idx is None:
                    idx = len(verts)
                    lookup[key] = idx
                    verts.append((ip[0], ip[1], ip[2]))
                    uvs.append((iu, iv))
                corner.append(idx)

            if flip_winding:
                corner = [corner[0], corner[2], corner[1]]
            indices.extend(corner)

        return pack_mesh(verts, uvs, indices, tex_w, tex_h), len(verts), len(indices) // 3, warnings
    finally:
        eval_obj.to_mesh_clear()


class ExportPsxMesh(bpy.types.Operator, ExportHelper):
    """Export the active mesh object as a PSX mesh"""
    bl_idname = "export_mesh.psx"
    bl_label = "Export PSX mesh"
    filename_ext = ".psm"

    scale: FloatProperty(
        name="Scale", default=100.0, min=0.001,
        description="Blender units to integer GTE units (1 unit -> this many)")
    tex_w: IntProperty(name="Texture width", default=64, min=1, max=256)
    tex_h: IntProperty(name="Texture height", default=64, min=1, max=256)
    flip_v: BoolProperty(name="Flip V", default=True,
                         description="Blender V is bottom-up, TIM images are top-down")
    flip_winding: BoolProperty(name="Flip winding", default=False)
    apply_transform: BoolProperty(name="Apply object transform", default=True)

    def execute(self, context):
        obj = context.active_object
        if obj is None or obj.type != 'MESH':
            self.report({'ERROR'}, "Select a mesh object")
            return {'CANCELLED'}
        try:
            data, nv, nt, warn = build_mesh(
                obj, context.evaluated_depsgraph_get(), self.scale,
                self.tex_w, self.tex_h, self.flip_v, self.flip_winding,
                self.apply_transform)
        except ValueError as e:
            self.report({'ERROR'}, str(e))
            return {'CANCELLED'}

        with open(self.filepath, "wb") as f:
            f.write(data)

        if warn["uv_range"]:
            self.report({'WARNING'}, "%d UV corners were outside 0..1 and got clamped" % warn["uv_range"])
        if warn["coord_range"]:
            self.report({'WARNING'}, "%d coordinates exceeded 16 bits; lower the scale" % warn["coord_range"])
        self.report({'INFO'}, "%d vertices, %d triangles, %d bytes" % (nv, nt, len(data)))
        return {'FINISHED'}


def menu_func(self, context):
    self.layout.operator(ExportPsxMesh.bl_idname, text="PSX mesh (.psm)")


def register():
    bpy.utils.register_class(ExportPsxMesh)
    bpy.types.TOPBAR_MT_file_export.append(menu_func)


def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(menu_func)
    bpy.utils.unregister_class(ExportPsxMesh)


if __name__ == "__main__":
    register()
