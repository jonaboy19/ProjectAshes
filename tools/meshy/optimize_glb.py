"""Turn a raw Meshy GLB (often millions of triangles) into mobile-ready LOD GLBs.

Usage (headless Blender 5.x):
  blender -b --python tools/meshy/optimize_glb.py -- <raw.glb> <out_dir> <name> <budget>

<budget> picks the triangle/texture tiers below. Output: <name>_lod0.glb, <name>_lod1.glb
Textures are embedded as JPEG; Godot re-compresses them to VRAM formats (ETC2/ASTC) on import.
"""
import bpy, sys, os

BUDGETS = {
    # tier: [(lod tag, triangles, texture px), ...]
    "hero":     [("lod0", 40000, 2048), ("lod1", 12000, 1024)],   # guild, inn, smithy, healer, keep
    "house":    [("lod0", 20000, 1024), ("lod1", 6000, 512)],     # ordinary homes, sheds, stalls
    "prop":     [("lod0", 4000, 512),   ("lod1", 1200, 256)],     # barrels, carts, benches, signs
    "small":    [("lod0", 1500, 512),   ("lod1", 500, 256)],      # weapons, items, clutter
    # thin geometry (stall canopies, awnings, poles) shreds when collapsed further:
    # feed a Meshy remesh at ~4k in and keep the mesh, only shrink the texture for lod1
    "thin":     [("lod0", 4000, 512),   ("lod1", 4000, 256)],
    "creature": [("lod0", 15000, 1024), ("lod1", 5000, 512)],     # rigged mobs (rig lod0 first)
}

src, outdir, name, budget = sys.argv[-4:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.context.view_layer.objects.active = meshes[0]
for o in bpy.data.objects:
    o.select_set(o in meshes)
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.object.mode_set(mode='OBJECT')


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


print("RAW", name, tris(obj))
for tag, target, tex in BUDGETS[budget]:
    # Collapse stalls early on AI meshes full of loose islands, so repeat passes;
    # if still over budget, weld small gaps and try again.
    for attempt in range(8):
        if tris(obj) <= target * 1.05:
            break
        if attempt == 4:
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.remove_doubles(threshold=0.002)
            bpy.ops.object.mode_set(mode='OBJECT')
        m = obj.modifiers.new("dec", 'DECIMATE')
        m.ratio = max(0.05, target / tris(obj))
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec")
    for img in bpy.data.images:
        if img.size[0] > tex:
            img.scale(tex, tex)
    for o in bpy.data.objects:
        o.select_set(o == obj)
    path = os.path.join(outdir, f"{name}_{tag}.glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
                              export_image_format='JPEG', export_jpeg_quality=88)
    print("TIER", name, tag, tris(obj), f"{tex}px", os.path.getsize(path) // 1024, "KB")
