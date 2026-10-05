"""Rigged Meshy biped (withSkin GLB): decimate the skinned mesh (keeps weights + UVs), shrink texture, keep armature + the baked animation clip.
Usage: blender -b --python optimize_rigged.py -- <src.glb> <out.glb> <tris> <tex_px> [lod1_ratio=0]
Meshy biped skeleton = 24 Mixamo-style bones (Hips, Spine/Spine01/Spine02, neck, Head, Left/RightArm...), retargetable to the UAL humanoid via Godot BoneMap."""
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:]
src, out, target, tex = a[0], a[1], int(a[2]), int(a[3])
lod1 = float(a[4]) if len(a) > 4 else 0.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and not o.vertex_groups:   # helper icospheres
        bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in bpy.data.objects: o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1: bpy.ops.object.join()
m = bpy.context.view_layer.objects.active

def tris(o):
    o.data.calc_loop_triangles(); return len(o.data.loop_triangles)
def decimate(o, tgt):
    n0 = tris(o)
    for _ in range(4):
        if tris(o) <= tgt * 1.03: break
        d = o.modifiers.new("dec", 'DECIMATE'); d.ratio = max(0.01, tgt / tris(o)); d.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=d.name) if d.name in o.modifiers else None
    return n0
def shrink(px):
    for i in bpy.data.images:
        if max(i.size) > px: i.scale(px, px)
def export(path, tag):
    for o in bpy.data.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=85, export_animations=True)
    print("BAKED", tag, "->", tris(m), f"{px_}px", os.path.getsize(path) // 1024, "KB", "bones", len([b for o in bpy.data.objects if o.type=='ARMATURE' for b in o.data.bones]))
for mod in list(m.modifiers):
    if mod.type == 'ARMATURE':
        bpy.context.view_layer.objects.active = m
        while m.modifiers[0] != mod: bpy.ops.object.modifier_move_up(modifier=mod.name)
src_tris = decimate_n = None
bpy.context.view_layer.objects.active = m
n0 = tris(m)
# decimate (armature modifier stays on top; apply decimate explicitly)
for _ in range(4):
    if tris(m) <= target * 1.03: break
    d = m.modifiers.new("dec", 'DECIMATE'); d.ratio = max(0.01, target / tris(m)); d.use_collapse_triangulate = True
    while m.modifiers[0] != d: bpy.ops.object.modifier_move_up(modifier=d.name)
    bpy.ops.object.modifier_apply(modifier=d.name)
px_ = tex
shrink(tex)
os.makedirs(os.path.dirname(out), exist_ok=True)
print("SRC_TRIS", n0)
export(out, os.path.basename(out))
