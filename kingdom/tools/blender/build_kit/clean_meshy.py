"""Clean Meshy free-pack models into build_kit LOD0 GLBs.
Run: blender -b --factory-startup --python clean_meshy.py -- [--tex-scale F] [--only name,name]
Deterministic, re-runnable. Writes meshy_<name>_lod0.glb + _meshy_manifest_lod0.json
(make_lods_meshy.sh then makes LODs and the final _meshy_manifest.json).
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
SRC = os.path.join(REPO, "kingdom", "assets", "incoming", "meshy_free")
OUT = os.path.join(REPO, "kingdom", "assets", "incoming", "build_kit")

# cat/name: (height m, role, texture cap px, yaw degrees about Godot Y)
ITEMS = {
 "market/stall_potatoes": (2.8, "wood", 1024, 0),
 "market/stall_open_roof": (3.0, "roof", 1024, 0),
 "market/stall_meat_shingle": (3.0, "roof", 1024, 0),
 "market/shed_striped_awning": (3.2, "cloth", 1024, 0),
 "props/well_stone_roofed": (3.4, "stone", 1024, 0),
 "props/well_covered_planks": (2.6, "wood", 1024, 0),
 "props/chest_metal_wood": (0.8, "wood", 512, 0),
 "props/chest_copper_lock": (0.8, "wood", 512, 0),
 "interior/bed_canopy_red": (2.4, "cloth", 512, 0),
 "interior/bookshelf_tall_rustic": (2.2, "wood", 512, 0),
 "furniture/table_tavern_trestle": (0.9, "wood", 512, 0),
 "furniture/chair_simple_a": (1.0, "wood", 512, 0),
 "furniture/tavern_set_barrels_b": (1.4, "wood", 512, 0),
 "lighting/lamp_post_timber_cross": (3.8, "timber", 512, 0),
 "lighting/street_lantern_gothic": (3.8, "iron", 512, 0),
 "lighting/lantern_wall_iron": (0.8, "iron", 512, 0),
 "banners/banner_stand_iron_frame": (3.2, "iron", 512, 0),
 "farm/hay_bale_round": (1.3, "thatch", 512, 0),
 "farm/hay_bale_rect_a": (0.9, "thatch", 512, 0),
 "farm/shed_thatch_small": (3.2, "thatch", 1024, 0),
 "farm/chicken_coop_fenced": (2.0, "wood", 512, 0),
 "fences/fence_picket_low": (1.0, "wood", 512, 0),
 "fences/fence_board_gate": (1.4, "wood", 512, 90),
 "fences/wall_stone_railing": (1.2, "stone", 512, 0),
 "signs/sign_blank_bracket": (1.4, "wood", 512, 0),
 "signs/sign_shop_lion": (1.6, "wood", 512, 0),
 "castle/wall_battlement_block": (4.5, "stone", 512, 0),
 "castle/tower_octagon_wall": (9.0, "stone", 512, 0),
 "water/bridge_stone_wood_deck": (3.0, "stone", 512, 0),
 "water/dock_circular_wood": (1.2, "wood", 512, 0),
}
MAX_TRIS = 6000
DECIMATE_TO = 5000

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TEX_SCALE = 1.0
ONLY = None
for i, a in enumerate(args):
    if a == "--tex-scale": TEX_SCALE = float(args[i + 1])
    if a == "--only": ONLY = set(args[i + 1].split(","))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def tri_count(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def bounds(objs):
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    return mn, mx


def process(key, spec):
    height, role, cap, yaw = spec
    name = key.split("/")[1]
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, key + "_lod0.glb"))
    ms = meshes()
    # bake each mesh's world transform, then join
    for o in ms:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action='DESELECT')
    for o in ms:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    # cleanup: degenerate + loose + tiny islands
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges[:])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.faces.ensure_lookup_table()
    seen = set(); islands = []
    for f in bm.faces:
        if f.index in seen: continue
        st = [f]; seen.add(f.index); isl = [f]
        while st:
            c = st.pop()
            for e in c.edges:
                for n in e.link_faces:
                    if n.index not in seen:
                        seen.add(n.index); st.append(n); isl.append(n)
        islands.append(isl)
    total = len(bm.faces)
    small = [f for isl in islands if len(isl) < max(4, total * 0.005) for f in isl]
    if small and len(small) < total * 0.05:
        bmesh.ops.delete(bm, geom=small, context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(obj.data); bm.free()
    t = tri_count([obj])
    if t > MAX_TRIS:
        m = obj.modifiers.new("dec", 'DECIMATE'); m.ratio = DECIMATE_TO / t
        bpy.ops.object.modifier_apply(modifier=m.name)
    if yaw:  # yaw about Godot Y == Blender Z
        obj.data.transform(Matrix.Rotation(math.radians(yaw), 4, 'Z'))
    mn, mx = bounds([obj])
    s = height / (mx.z - mn.z)
    obj.data.transform(Matrix.Scale(s, 4))
    mn, mx = bounds([obj])
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    obj.data.transform(Matrix.Translation(-c))
    obj.data.update()
    obj.name = "meshy_" + name
    obj.data.name = obj.name
    for slot in obj.material_slots:
        m = slot.material
        m.name = "%s_%s" % (name, role)
        for nd in m.node_tree.nodes:
            if nd.type == 'TEX_IMAGE' and nd.image:
                img = nd.image
                lim = max(64, int(cap * TEX_SCALE))
                w, h = img.size
                if max(w, h) > lim:
                    f = lim / max(w, h)
                    img.scale(max(1, int(w * f)), max(1, int(h * f)))
    out = os.path.join(OUT, "meshy_%s_lod0.glb" % name)
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=True, export_animations=False, export_cameras=False,
        export_lights=False, export_image_format='JPEG', export_jpeg_quality=85,
        export_materials='EXPORT')
    return out


def readback(path):
    reset()
    bpy.ops.import_scene.gltf(filepath=path)
    ms = meshes()
    tris = tri_count(ms)
    mn, mx = bounds(ms)
    # Blender Z-up -> glTF Y-up: (x, z, -y)
    a = [mn.x, mn.z, -mn.y]; b = [mx.x, mx.z, -mx.y]
    lo = [round(min(a[i], b[i]), 4) for i in range(3)]
    hi = [round(max(a[i], b[i]), 4) for i in range(3)]
    mats = sorted({s.material.name for o in ms for s in o.material_slots if s.material})
    return tris, lo, hi, mats


done = {}
for key, spec in ITEMS.items():
    name = key.split("/")[1]
    if ONLY and name not in ONLY: continue
    if not os.path.isfile(os.path.join(SRC, key + "_lod0.glb")):
        print("MISSING", key); continue
    out = process(key, spec)
    tris, lo, hi, mats = readback(out)
    done["meshy_" + name] = {"source": "meshy_free/" + key, "tris_lod0": tris, "tris_lod1": 0,
                             "aabb_min": lo, "aabb_max": hi, "materials": mats}
    print("DONE", name, tris, lo, hi, mats)

mp = os.path.join(OUT, "_meshy_manifest_lod0.json")
prev = json.load(open(mp)) if (ONLY and os.path.isfile(mp)) else {}
prev.update(done)
json.dump(prev, open(mp, "w"), indent=1, sort_keys=True)
