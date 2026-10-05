"""Tier-A hero LODs from a UAL-rigged Meshy character (skill ashes-hero-character).
LOD0 = Catmull-Clark x1 then decimate to `lod0` tris (smooth silhouette; weights + UVs interpolate), LOD1 = the 4k source,
LOD2 = decimated to `lod2` tris. Same skeleton, same texture.
tools/external/blender.sh tools/blender/hero_tier_a/smooth_lods.py -- <in.glb> <out_prefix> [lod0=14000] [lod2=2000]"""
import bpy, sys

a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
lod0 = int(a[2]) if len(a) > 2 else 14000
lod2 = int(a[3]) if len(a) > 3 else 2000


def load():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    return [o for o in bpy.data.objects if o.type == "MESH"][0]


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def apply_first(o, mod):
    bpy.context.view_layer.objects.active = o
    while o.modifiers.find(mod.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=False, export_skins=True,
                              export_image_format="JPEG", export_jpeg_quality=92)


import bmesh
m = load()
bm = bmesh.new(); bm.from_mesh(m.data)                 # glTF splits verts at UV seams: weld or the subsurf opens cracks
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
bm.to_mesh(m.data); bm.free()
s = m.modifiers.new("sub", "SUBSURF"); s.levels = 1; s.uv_smooth = "PRESERVE_BOUNDARIES"
apply_first(m, s)
d = m.modifiers.new("dec", "DECIMATE"); d.ratio = lod0 / tris(m)
apply_first(m, d)
bpy.ops.object.shade_smooth()
print("LOD0 tris", tris(m))
export(out + ".glb")
m = load()
bpy.context.view_layer.objects.active = m
bpy.ops.object.shade_smooth()
print("LOD1 tris", tris(m))
export(out + "_lod1.glb")
m = load()
d = m.modifiers.new("dec", "DECIMATE"); d.ratio = lod2 / tris(m)
apply_first(m, d)
print("LOD2 tris", tris(m))
export(out + "_lod2.glb")
