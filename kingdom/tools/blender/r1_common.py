"""Shared helpers for the Region 1 kit scripts (L3 exteriors, L4 rift kit). bpy, Blender 5.x."""
import bpy, bmesh, os, math
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
KINGDOM = os.path.abspath(os.path.join(HERE, "..", ".."))
ROOT = os.path.abspath(os.path.join(KINGDOM, ".."))
MESHY_FREE = os.path.join(KINGDOM, "assets", "incoming", "meshy_free")
GEN = os.path.join(KINGDOM, "assets", "generated")
R1 = os.path.join(KINGDOM, "assets", "incoming", "region1")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def tex_images(obj):
    out = []
    for m in obj.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image and n.image not in out:
                    out.append(n.image)
    return out


def rgb2hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1); mn = a.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = m & (mx == r); gc = m & (mx == g) & ~rc; bc = m & ~rc & ~gc
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv2rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s); q = v * (1 - f * s); t = v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for k, (r, g, b) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m, 0] = r[m]; out[m, 1] = g[m]; out[m, 2] = b[m]
    return out


def get_hsv(img):
    w, h_ = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h_, w, 4)
    return a, rgb2hsv(a[..., :3])


def set_rgb(img, a, rgb):
    a[..., :3] = rgb
    img.pixels = a.ravel()
    img.update()


def lin(hexstr):
    h = hexstr.lstrip("#"); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x ** 2.2 for x in c)


def flat_mat(name, hexstr, rough=0.75, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(hexstr), 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if emit:
        b.inputs["Emission Color"].default_value = (*lin(emit), 1); b.inputs["Emission Strength"].default_value = emit_strength
    return m


def add_obj(bm, name, mat, loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat); o.location = loc; o.rotation_euler = rot
    return o


def box_bm(sx, sy, sz):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return bm


def tri_count(objs=None):
    t = 0
    for o in (objs or bpy.context.scene.objects):
        if o.type == 'MESH':
            o.data.calc_loop_triangles(); t += len(o.data.loop_triangles)
    return t


def decimate_to(obj, target):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    obj.data.calc_loop_triangles(); n = len(obj.data.loop_triangles)
    if n <= target:
        return n
    md = obj.modifiers.new("dec", 'DECIMATE'); md.ratio = target / n
    bpy.ops.object.modifier_apply(modifier=md.name)
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def shrink_textures(obj, size):
    for img in tex_images(obj):
        if max(img.size) > size:
            img.scale(size, size)


def apply_transforms(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def export(path, objs=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in (objs or bpy.context.scene.objects):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_image_format='JPEG', export_jpeg_quality=88, export_yup=True)
    print("WROTE", path, os.path.getsize(path) // 1024, "KB")
