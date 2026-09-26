"""Turns heavy Poly Haven photo-scans (CC0) into game-ready meshes: decimates
each object to a triangle budget while keeping UVs and the scanned PBR
textures, and exports one GLB per object (rock sets become several rocks).
Run: python3 decimate_scans.py <polyhaven_models_dir> <out_dir>"""
import sys, os, bpy

src, out = sys.argv[-2], sys.argv[-1]
# name -> (triangle budget per object, split parts into separate files?)
JOBS = {
    "rock_moss_set_01": (1400, True),
    "rock_moss_set_02": (1400, True),
    "tree_stump_01": (1200, False),
    "tree_stump_02": (1200, False),
    "root_cluster_01": (2200, False),
    "dead_tree_trunk": (1400, False),
    "fern_02": (900, False),
    "shrub_03": (900, False),
    "dandelion_01": (500, False),
    "nettle_plant": (500, False),
    "stone_fire_pit": (1500, False),
    "wooden_crate_01": (600, False),
    "wicker_basket_01": (800, False),
    "wooden_bucket_01": (500, False),
}

def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)

for name, (budget, split) in JOBS.items():
    path = os.path.join(src, name, name + "_1k.gltf")
    if not os.path.exists(path):
        print("skip", name); continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    groups = [[o] for o in meshes] if split else [meshes]
    for gi, group in enumerate(groups):
        for o in group:
            before = tris(o)
            share = budget * (before / max(1, sum(tris(x) for x in group)))
            if before > share:
                m = o.modifiers.new("dec", 'DECIMATE')
                m.ratio = max(0.002, share / before)
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.modifier_apply(modifier="dec")
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:
            o.select_set(True)
        # Re-centre on the ground for split parts.
        if split:
            o = group[0]
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
            o.location.x = o.location.y = 0.0
            bb = [o.matrix_world @ v.co for v in o.data.vertices]
            o.location.z -= min(v.z for v in bb)
        fname = f"{name}_{gi + 1}.glb" if split else f"{name}.glb"
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, fname), export_format='GLB',
                                  use_selection=True, export_apply=True, export_image_format='JPEG')
        print("wrote", fname, sum(tris(o) for o in group), "tris")
